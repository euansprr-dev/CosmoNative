COSMO Sanctuary Evolution Plan

 Spatial-UX Architectural Brief v1.0

 ---
 EXECUTIVE SUMMARY

 This document defines the architectural evolution of the COSMO Sanctuary from a static
 hexagonal constellation into a living spatial map with two satellite regions: The 
 Plannerum (planning realm) and The Thinkspace (creative production area). The design draws
  inspiration from Destiny's world map spatial metaphor while preserving COSMO's elevated,
 mythic, spiritual-warrior aesthetic.

 Critical Scope Clarification:
 - Plannerum REPLACES the existing calendar system - not a separate layer
 - Must handle complete daily/weekly planning with time-based scheduling
 - Must integrate all inbox streams (ideas, project ideas, unscheduled tasks)
 - Must maintain ATOM architecture compatibility
 - All UI must feel unified within the COSMO world

 Key Constraints:
 - Preserve existing mist/fog background (user mandate)
 - Preserve typography and level system (user mandate)
 - Keep current animation systems intact
 - Refactor existing calendar - avoid duplicates
 - App must load to Sanctuary first (not Canvas)

 ---
 PART 1: CONCEPTUAL SPATIAL MAP

 1.1 High-Level Map Topology

                     ┌─────────────────┐
                     │   THINKSPACE    │
                     │  (right orbit)  │
                     │   ◐ satellite   │
                     └────────┬────────┘
                              │
                              │ ethereal connection
                              │
 ┌─────────────────┐          │          ┌─────────────────┐
 │   PLANNERUM     │──────────┼──────────│   SANCTUARY     │
 │  (left orbit)   │          │          │   (center core) │
 │   ◑ satellite   │──────────┴──────────│   ⬡ hexagon     │
 └─────────────────┘                      └─────────────────┘
                              │
                              │
                     ┌────────┴────────┐
                     │  INSIGHT STREAM │
                     │   (bottom dock) │
                     └─────────────────┘

 1.2 Spatial Positioning (Screen Coordinates)

 Desktop Layout (1440px+ width):

 | Element         | Position               | Size                | Z-Depth            |
 |-----------------|------------------------|---------------------|--------------------|
 | Sanctuary Core  | Center (50%, 45%)      | 480pt constellation | 0 (base)           |
 | Plannerum Node  | Left (12%, 50%)        | 72pt orb            | -50pt (recessed)   |
 | Thinkspace Node | Right (88%, 50%)       | 72pt orb            | -50pt (recessed)   |
 | Insight Stream  | Bottom (50%, 92%)      | Full-width, 140pt   | +20pt (foreground) |
 | Header/Levels   | Top-left (40pt, 40pt)  | Auto                | +30pt (foreground) |
 | Live Indicator  | Top-right (40pt inset) | 120pt x 80pt        | +30pt (foreground) |

 Connection Lines:
 - Plannerum → Sanctuary Core: Curved bezier, 40% opacity, subtle pulse
 - Thinkspace → Sanctuary Core: Curved bezier, 40% opacity, subtle pulse
 - NO direct Plannerum ↔ Thinkspace connection (they orbit the core, not each other)

 1.3 Visual Hierarchy

 FOREGROUND (+30pt)
 ├── Header: "SANCTUARY" + Level System
 ├── Live Indicator (Focus/Energy)
 └── Navigation hints (hover states)

 MID-GROUND (0pt)
 ├── Sanctuary Constellation (6 dimension orbs)
 ├── Hero Orb (Cosmo Index)
 └── Insight Stream cards

 BACKGROUND (-50pt)
 ├── Plannerum satellite node
 ├── Thinkspace satellite node
 ├── Connection threads (orbital paths)
 └── Mist/fog layers (PRESERVED)

 DEEP BACKGROUND (-100pt)
 └── Aurora gradient / Metal shader

 ---
 PART 2: SANCTUARY POLISH SPECIFICATIONS

 2.1 Elements to PRESERVE (Non-Negotiable)

 1. Mist/Fog Background - Exact current implementation
 2. Typography - "SANCTUARY" header, level text, dimension labels
 3. Level System Display - "Level 0 · Transcendent" format
 4. XP Progress Bar - Current style and position
 5. Live Indicator - Top-right Focus/Energy display
 6. Dimension Colors - Cyan, Amber, Green, Blue, Purple, Teal
 7. Core Animation - Entry reveal sequence, breathing, rotation

 2.2 Polish Enhancements

 2.2.1 Hero Orb Refinements

 Current: Solid purple gradient with CI label
 Enhancement:
 - Add subtle inner glow ring (white, 5% opacity)
 - Introduce micro-particle drift inside orb (3-5 particles, slow float)
 - Deepen the glass depth effect with secondary reflection layer
 - Add faint orbital ring at 120% radius (hairline, 15% opacity)

 2.2.2 Dimension Orb Refinements

 Current: Solid color circles with icon + level number
 Enhancement:
 - Add subtle outer glow halo (dimension color, 20% opacity, 8pt blur)
 - Introduce breathing scale animation (1.0 → 1.02 → 1.0, 4s cycle, staggered)
 - On hover: Gentle lift effect (translateY: -4pt, scale: 1.05)
 - Connection lines should pulse subtly when orb is hovered

 2.2.3 Connection Line Refinements

 Current: Static colored lines between orbs
 Enhancement:
 - Add gradient flow animation (energy traveling along lines)
 - Introduce subtle width modulation (1pt → 1.5pt → 1pt, 6s cycle)
 - On dimension hover: Connected lines brighten to 60% opacity
 - Add faint glow along line path (4pt blur, 10% opacity)

 2.2.4 Insight Stream Refinements

 Current: Horizontal card carousel with pagination dots
 Enhancement:
 - Add subtle parallax shift on mouse movement (±8pt range)
 - Cards should have soft shadow depth (0, 8pt, 24pt, black 15%)
 - Active card: Slight scale lift (1.02x)
 - Add ambient glow beneath stream area (gradient fade, matches mist)

 2.3 Revised Aesthetic Specification

 Color System (Expanded)

 // Core Palette (PRESERVED)
 --sanctuary-void: #0A0A0F
 --sanctuary-mist: rgba(255, 255, 255, 0.03)

 // Dimension Colors (PRESERVED)
 --cognitive: #6366F1    // Indigo
 --creative: #F59E0B     // Amber
 --physiological: #10B981 // Emerald
 --behavioral: #3B82F6   // Blue
 --knowledge: #8B5CF6    // Purple
 --reflection: #EC4899   // Pink

 // NEW: Satellite Region Colors
 --plannerum-primary: #A78BFA    // Soft violet (planning = foresight)
 --plannerum-glow: rgba(167, 139, 250, 0.3)
 --thinkspace-primary: #34D399   // Soft mint (creation = growth)
 --thinkspace-glow: rgba(52, 211, 153, 0.3)

 // NEW: Connection Thread Colors
 --thread-dormant: rgba(255, 255, 255, 0.15)
 --thread-active: rgba(255, 255, 255, 0.4)
 --thread-pulse: rgba(255, 255, 255, 0.6)

 Depth Cues

 | Layer      | Blur | Opacity | Scale | Description                |
 |------------|------|---------|-------|----------------------------|
 | Foreground | 0    | 100%    | 1.0   | UI chrome, active elements |
 | Mid-ground | 0    | 100%    | 1.0   | Main constellation         |
 | Background | 2pt  | 70%     | 0.85  | Satellite nodes            |
 | Deep BG    | 8pt  | 40%     | 0.7   | Distant elements, aurora   |

 Glyph & Icon Style

 Principle: Geometric, clean, single-stroke where possible

 Satellite Node Icons:
 - Plannerum: Compass rose or astrolabe motif (planning/direction)
 - Thinkspace: Nested squares or infinite canvas symbol (creation/space)

 Connection Glyphs:
 - Use subtle diamond waypoints along connection lines
 - Waypoints pulse when data flows between regions

 ---
 PART 3: PLANNERUM DESIGN

 3.1 Conceptual Identity

 The Plannerum is a holographic command chamber where your next moves take shape.

 CRITICAL: Plannerum REPLACES the existing calendar system entirely.

 It is NOT:
 - A traditional grid calendar (boring rows/columns)
 - A Trello board
 - A simple to-do list
 - A secondary layer on top of calendar

 It IS:
 - The complete time-planning interface for COSMO
 - A spatial constellation of missions, arcs, and time blocks
 - An ambient flow of incoming streams (all inboxes unified)
 - A calm but comprehensive overview of all commitments
 - Fully integrated with ATOM architecture

 3.2 Entry & Exit

 Entry:
 1. User clicks Plannerum satellite node on Sanctuary map
 2. Sanctuary constellation fades (opacity: 0.2, scale: 0.95)
 3. Plannerum view zooms in from left (scale: 0.8 → 1.0, opacity: 0 → 1)
 4. Transition duration: 500ms, easeOutExpo

 Exit:
 1. User clicks "Return to Sanctuary" or presses Escape
 2. Plannerum fades out (scale: 1.0 → 0.9, opacity: 1 → 0)
 3. Sanctuary constellation restores (opacity: 1, scale: 1.0)
 4. Transition duration: 400ms, easeInOut

 3.3 Plannerum Layout Architecture

 Three-Panel Design with Temporal Navigation

 ┌─────────────────────────────────────────────────────────────────────────────┐
 │  PLANNERUM                                          ← Return to Sanctuary   │
 │  "Shape your next chapter"                          [Day] [Week] [Month]    │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │                                                                             │
 │  ┌───────────────┐  ┌─────────────────────────────────────────────────────┐ │
 │  │   INBOXES     │  │              TEMPORAL CANVAS                        │ │
 │  │   (Left Rail) │  │              (Main View)                            │ │
 │  │               │  │                                                     │ │
 │  │  ◈ Ideas      │  │  ┌─────────────────────────────────────────────┐   │ │
 │  │    ┊ 3 new    │  │  │  TODAY: Monday, December 23                 │   │ │
 │  │               │  │  │                                             │   │ │
 │  │  ◈ Tasks      │  │  │   06  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │   │ │
 │  │    ┊ 7 open   │  │  │   07  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │   │ │
 │  │               │  │  │   08  ████ Deep Work: Draft chapter ████   │   │ │
 │  │  ◈ Project:   │  │  │   09  ████████████████████████████████████   │   │ │
 │  │    Cosmo      │  │  │   10  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │   │ │
 │  │    ┊ 2 new    │  │  │   11  ████ Review: Client call ████████   │   │ │
 │  │               │  │  │   12  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │   │ │
 │  │  ◈ Content    │  │  │   ...                                       │   │ │
 │  │    Pipeline   │  │  │                                             │   │ │
 │  │    ┊ 1 ready  │  │  └─────────────────────────────────────────────┘   │ │
 │  │               │  │                                                     │ │
 │  │  ─────────    │  │  [Week view shows 7-day arc with blocks as orbs]   │ │
 │  │               │  │  [Month view shows density heat map]               │ │
 │  │  + New Inbox  │  │                                                     │ │
 │  └───────────────┘  └─────────────────────────────────────────────────────┘ │
 │                                                                             │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │  ACTIVE FOCUS: Deep Work - Draft chapter    ⏱ 1:23:45    [Pause] [Complete]│
 └─────────────────────────────────────────────────────────────────────────────┘

 3.3.1 View Modes (Non-Boring Calendar Approach)

 DAY VIEW - "The Timeline"
 - Vertical time ribbon (NOT a grid)
 - Hours flow as a continuous stream, not rigid boxes
 - Scheduled blocks appear as floating glass cards along the timeline
 - Unscheduled time appears as soft gradient zones ("open space")
 - Current time: Glowing horizontal marker that pulses
 - Drag from inbox → Drop onto timeline to schedule
 - Visual style: Glass cards with dimension-colored accents

 WEEK VIEW - "The Arc"
 - 7 days displayed as constellation points on a horizontal arc
 - Each day: Orb showing density (size/glow = commitment level)
 - Scheduled blocks: Smaller orbs orbiting their day
 - Multi-day arcs: Curved connection lines between days
 - Current day: Brightest, centered
 - Click day orb → Zooms to Day view for that day
 - Visual style: Spatial, Destiny-inspired, no grid lines

 MONTH VIEW - "The Density Map"
 - Calendar-like grid BUT with COSMO aesthetic
 - Days as subtle glass cells (not harsh borders)
 - Color intensity = commitment density
 - Week rows flow as horizontal bands
 - Hover day → Preview tooltip with key blocks
 - Click day → Zooms to Day view
 - Visual style: Heat map with glass morphism, fog at edges

 3.3.2 Time Block Design (The Core Calendar Unit)

 Block Visual Identity:
 ┌────────────────────────────────────────┐
 │ ◈ [Dimension Icon]   09:00 - 11:00     │
 │                                        │
 │   Deep Work: Draft chapter 3           │
 │   ┊ Project: Cosmo                     │
 │                                        │
 │   [/////// Progress: 45% ///////]      │
 │                                        │
 │   🔗 Linked: 2 ideas, 1 task           │
 └────────────────────────────────────────┘

 Block Properties:
 - Title (required)
 - Time range (start/end)
 - Dimension type (Cognitive, Creative, etc.) - determines color accent
 - Linked atoms (ideas, tasks, research) from ATOM system
 - Duration estimate vs actual tracking
 - Completion status

 Block States:
 - Scheduled (solid glass card)
 - In Progress (glowing border, timer visible)
 - Completed (check mark, subtle green tint, XP awarded)
 - Overdue (soft amber warning glow, not alarming red)
 - Conflicting (overlapping warning indicator)

 3.4 Plannerum Component Specifications

 3.4.1 Inbox Streams Panel (Left Side)

 Purpose: Surface uncommitted items requiring attention

 Visual Style:
 - Vertical stack of inbox entries
 - Each inbox: Icon + Label + Count badge
 - Glass card container (8% white, 1pt border)
 - Subtle glow on items with new content

 Inbox Types:
 1. Ideas Inbox - All uncommitted ideas (global)
 2. Tasks Inbox - Unscheduled tasks (global)
 3. Per-Project Inboxes - Dynamically generated for each active project

 Interaction:
 - Click inbox → Expands to show items inline (accordion style)
 - Drag item from inbox → Opens assignment modal
 - Items can be promoted to Mission Queue

 Empty State:
 - Soft message: "All streams clear"
 - Subtle checkmark glyph
 - No harsh "empty" messaging

 3.4.2 Weekly Arc View (Top Right)

 Purpose: Non-calendar view of the week's trajectory

 Visual Style:
 - Horizontal timeline ribbon (NOT a grid)
 - Days represented as waypoints on a path
 - Current day: Glowing marker
 - Focus blocks: Constellation points floating near their day

 Key Differences from Calendar:
 - No rigid time slots
 - No hour-by-hour breakdown
 - Focus on relative positioning and flow
 - Emphasis on "arcs" (multi-day commitments) not appointments

 Data Displayed:
 - Scheduled focus blocks (as floating orbs)
 - Commitment density per day (glow intensity)
 - Arc lines connecting multi-day work

 Interaction:
 - Hover day → Shows day summary tooltip
 - Click day → Zooms to daily planning view
 - Drag focus block → Reschedules visually

 3.4.3 Mission Queue (Bottom Right)

 Purpose: Prioritized list of immediate commitments

 Visual Style:
 - Vertical stack with priority ordering
 - Each mission: Type icon + Title + Duration estimate
 - Subtle connecting line showing sequence
 - Glass card styling consistent with Sanctuary

 Mission Types:
 - Deep Work (brain icon, cognitive color)
 - Creative (brush icon, creative color)
 - Administrative (calendar icon, behavioral color)
 - Review (eye icon, neutral)

 Interaction:
 - Drag to reorder
 - Click to expand details
 - Complete → XP animation + removal
 - Links to related Sanctuary dimensions

 3.4.4 Today's Focus Bar (Bottom Dock)

 Purpose: Immediate action context

 Visual Style:
 - Full-width bar at bottom
 - Shows: Current focus block (if active) or next scheduled
 - XP potential indicator ("Complete this for +25 XP")
 - Quick-action buttons: Start Focus, Skip, Defer

 3.5 Plannerum Aesthetic Rules

 Color Application:
 - Primary surfaces: Dark void (#0A0A0F) with glass overlays
 - Accent color: Plannerum violet (#A78BFA) for selected items
 - Dimension colors: Applied to mission type indicators
 - Borders: 1pt, 10% white

 Typography:
 - Header: Same as Sanctuary ("PLANNERUM")
 - Subheader: "Shape your next chapter" (14pt, 50% opacity)
 - Body: System font, 15pt
 - Labels: 11pt, 60% opacity

 Animation:
 - Items enter with stagger (40ms delay each)
 - Selection: Gentle scale (1.0 → 1.02)
 - Completion: Particle burst + fade out

 3.6 Plannerum Edge Cases

 | Scenario                  | Handling                                       |
 |---------------------------|------------------------------------------------|
 | No items in any inbox     | Show "All streams clear" with ambient glow     |
 | 50+ items in inbox        | Collapse to summary count, expand on click     |
 | No scheduled focus blocks | Weekly arc shows "Open space" message          |
 | Conflicting time blocks   | Visual overlap indicator (orange warning glow) |
 | Past due items            | Subtle red accent, but not alarming            |
 | Weekend days              | Shown but de-emphasized (30% opacity)          |

 ---
 PART 4: THINKSPACE INTEGRATION

 4.1 Conceptual Identity

 The Thinkspace is the infinite creative production realm - your Canvas.

 It already exists as the main Canvas view. This integration simply:
 1. Adds it as a satellite node on the Sanctuary map
 2. Creates a smooth transition between Sanctuary and Canvas

 4.2 Thinkspace Node Design

 Visual:
 - 72pt orb (same size as dimension orbs)
 - Color: Soft mint (#34D399)
 - Icon: Nested squares or infinite canvas symbol
 - Label: "Thinkspace" (below orb)
 - Orbital ring: Hairline, 20% opacity, slow rotation

 Position:
 - Right side of Sanctuary (88% x, 50% y)
 - Slightly recessed in z-depth (-50pt)
 - Connected to hero orb via curved bezier line

 States:
 - Idle: Subtle breathing (1.0 → 1.02 → 1.0)
 - Hover: Lift + glow intensify + label highlight
 - Active: N/A (transitions to full Canvas view)

 4.3 Entry Transition (Sanctuary → Canvas)

 Sequence (600ms total):

 0ms:     User clicks Thinkspace node
 0-100ms: Node pulses (scale: 1.0 → 1.15)
 100-400ms:
   - Sanctuary fades (opacity: 1 → 0)
   - Thinkspace node scales up (1.0 → screen fill)
   - Mist intensifies briefly (fog density +20%)
 400-600ms:
   - Canvas view fades in (opacity: 0 → 1)
   - Canvas blocks animate to positions
 600ms:   Canvas fully interactive

 4.4 Exit Transition (Canvas → Sanctuary)

 Trigger: Click Level Orb (top-left) or dedicated "Return to Sanctuary" action

 Sequence (500ms total):

 0ms:     User triggers return
 0-200ms:
   - Canvas fades (opacity: 1 → 0)
   - Slight scale down (1.0 → 0.95)
 200-500ms:
   - Sanctuary fades in (opacity: 0 → 1)
   - Constellation animates in (reuse existing reveal sequence)
   - Thinkspace node returns to orbital position
 500ms:   Sanctuary fully interactive

 4.5 Thinkspace Badge Indicators

 Show activity indicators on the Thinkspace node when viewed from Sanctuary:

 - Active blocks count: Small badge showing # of canvas blocks
 - Recent activity: Glow pulse if canvas modified in last hour
 - Focus mode available: Indicator if uncommitted work exists

 ---
 PART 5: NAVIGATION ARCHITECTURE

 5.1 App Entry Point Change

 Current: App loads to Canvas (CanvasView)
 Required: App loads to Sanctuary first

 Implementation:
 // MainView.swift change
 @State private var showingSanctuary: Bool = true  // Changed from false

 First-Launch Sequence:
 1. App opens
 2. Sanctuary view loads with full reveal animation
 3. User sees their neural constellation
 4. User can navigate to Plannerum, Thinkspace, or dive into dimensions

 5.2 Navigation Flow Diagram

                          APP LAUNCH
                               │
                               ▼
                     ┌─────────────────┐
                     │    SANCTUARY    │◄────────────────────┐
                     │  (home state)   │                     │
                     └────────┬────────┘                     │
                              │                              │
            ┌─────────────────┼─────────────────┐            │
            │                 │                 │            │
            ▼                 ▼                 ▼            │
     ┌────────────┐    ┌────────────┐    ┌────────────┐     │
     │ PLANNERUM  │    │ DIMENSION  │    │ THINKSPACE │     │
     │            │    │   DETAIL   │    │  (Canvas)  │     │
     └──────┬─────┘    └──────┬─────┘    └──────┬─────┘     │
            │                 │                 │            │
            │                 │                 │            │
            └─────────────────┴─────────────────┴────────────┘
                          (Return actions)

 5.3 Keyboard Navigation

 | Key    | Action                              |
 |--------|-------------------------------------|
 | Escape | Return to Sanctuary (from any view) |
 | P      | Open Plannerum (from Sanctuary)     |
 | T      | Open Thinkspace (from Sanctuary)    |
 | 1-6    | Quick-jump to dimension 1-6         |
 | Cmd+K  | Command Hub (always available)      |

 5.4 Voice Navigation (Existing System)

 Add new voice commands:
 - "Open Plannerum" / "Show planning"
 - "Open Thinkspace" / "Go to canvas"
 - "Return to Sanctuary" / "Go home"

 ---
 PART 6: ANIMATION CONSISTENCY

 6.1 Shared Animation Tokens

 All transitions should use the existing SanctuaryTokens.Springs:

 | Animation Type      | Spring Config                 |
 |---------------------|-------------------------------|
 | Quick response      | response: 0.2, damping: 0.85  |
 | Standard transition | response: 0.35, damping: 0.78 |
 | Cinematic zoom      | response: 0.6, damping: 0.75  |
 | Bounce effect       | response: 0.4, damping: 0.6   |

 6.2 Transition Matrix

 | From       | To         | Animation            | Duration |
 |------------|------------|----------------------|----------|
 | Sanctuary  | Plannerum  | Fade + slide left    | 500ms    |
 | Sanctuary  | Thinkspace | Fade + zoom expand   | 600ms    |
 | Sanctuary  | Dimension  | Zoom in (existing)   | 400ms    |
 | Plannerum  | Sanctuary  | Fade + slide right   | 400ms    |
 | Thinkspace | Sanctuary  | Zoom contract + fade | 500ms    |
 | Dimension  | Sanctuary  | Zoom out (existing)  | 400ms    |

 6.3 Preserve Existing Animations

 DO NOT MODIFY:
 - SanctuaryAnimationChoreographer entry sequence
 - Hero orb breathing and rotation
 - Dimension orb breathing cycles
 - Connection line glow modulation
 - Insight stream parallax

 EXTEND ONLY:
 - Add satellite node breathing (same pattern as dimension orbs)
 - Add connection thread pulse for satellite connections
 - Add entry/exit sequences for new regions

 ---
 PART 7: RESPONSIVE CONSIDERATIONS

 7.1 Breakpoint Strategy

 | Width       | Layout Adjustment                                   |
 |-------------|-----------------------------------------------------|
 | 1440px+     | Full layout as specified                            |
 | 1200-1439px | Satellite nodes move closer to center (15% / 85% x) |
 | 1024-1199px | Plannerum/Thinkspace labels hidden, icon-only       |
 | < 1024px    | Satellite nodes become footer buttons               |

 7.2 Small Screen Adaptations

 iPad / Narrow Window:
 - Satellite nodes relocate to bottom bar
 - Tap to expand into sheet modal
 - Sanctuary constellation remains centered
 - Insight stream becomes swipeable cards

 7.3 Performance Considerations

 - Satellite nodes: Simple views (not Metal-rendered)
 - Connection threads: Canvas drawing (not Metal)
 - Plannerum: Standard SwiftUI (no Metal shaders)
 - Only Sanctuary core uses Metal rendering

 ---
 PART 8: XP INTEGRATION

 8.1 Plannerum XP Events

 | Action                    | XP Award  | Dimension      |
 |---------------------------|-----------|----------------|
 | Complete mission          | 10-50 XP  | Varies by type |
 | Clear inbox item          | 5 XP      | Cognitive      |
 | Plan week (Sunday ritual) | 25 XP     | Behavioral     |
 | Maintain streak           | 15 XP/day | Behavioral     |

 8.2 Visual XP Feedback

 - Mission completion: Particle burst from mission → hero orb direction
 - Streak milestone: Connection threads pulse in sequence
 - Level up: Full ceremony (existing animation)

 8.3 Sanctuary Recalibration

 When Plannerum changes affect dimensions:
 1. User completes cognitive mission in Plannerum
 2. Return to Sanctuary
 3. Cognitive dimension orb pulses (new XP indicator)
 4. Hero orb CI value updates with animation

 ---
 PART 9: IMPLEMENTATION SEQUENCE

 Phase 1: Foundation (Sanctuary + Satellites)

 1. Change app entry point to Sanctuary (MainView.swift)
 2. Create SatelliteNodeView.swift - reusable satellite orb component
 3. Add Plannerum satellite node (left, violet)
 4. Add Thinkspace satellite node (right, mint)
 5. Create SanctuaryConnectionThread.swift - curved bezier connections
 6. Add connection threads from satellites to hero orb
 7. Implement basic node click → transition stub

 Phase 2: Plannerum Container & Navigation

 8. Create UI/Plannerum/ directory structure
 9. Create PlannerumView.swift - main container with view mode state
 10. Create PlannerumTokens.swift - design tokens (colors, springs, sizes)
 11. Implement Sanctuary → Plannerum full-screen transition
 12. Implement Plannerum → Sanctuary return transition
 13. Add view mode switcher (Day/Week/Month)

 Phase 3: Plannerum Inbox Rail

 14. Create InboxRailView.swift - left panel container
 15. Create InboxStreamRow.swift - individual inbox entry
 16. Integrate with existing InboxViewBlock data model
 17. Add project-specific inboxes (dynamic generation)
 18. Implement inbox expansion/collapse accordion
 19. Connect to ATOM system for real inbox data

 Phase 4: Plannerum Day View

 20. Create DayTimelineView.swift - vertical time ribbon
 21. Create TimeBlockCard.swift - glass card for scheduled blocks
 22. Implement time marker (current time indicator)
 23. Implement drag-to-schedule from inbox
 24. Implement block creation/editing modal
 25. Connect to existing scheduleBlock ATOM type

 Phase 5: Plannerum Week View

 26. Create WeekArcView.swift - constellation-style week
 27. Create DayOrb.swift - day representation with density
 28. Implement multi-day arc connections
 29. Implement day orb → day view zoom transition
 30. Connect to scheduled blocks data

 Phase 6: Plannerum Month View

 31. Create MonthDensityView.swift - heat map calendar
 32. Implement glass cell styling (non-boring)
 33. Implement day hover preview
 34. Implement day → day view zoom

 Phase 7: Focus & Timer Integration

 35. Create ActiveFocusBar.swift - bottom dock component
 36. Integrate with existing deep work block system
 37. Implement timer display and controls
 38. Connect XP award on completion

 Phase 8: Thinkspace Transition

 39. Implement Sanctuary → Canvas transition (scale-up from node)
 40. Modify existing Canvas → Sanctuary to use reverse animation
 41. Ensure Level Orb returns to Sanctuary (not toggle behavior)

 Phase 9: Sanctuary Polish

 42. Apply hero orb refinements (inner glow, particles, orbital ring)
 43. Apply dimension orb refinements (halo glow, hover lift)
 44. Apply connection line refinements (gradient flow, width modulation)
 45. Apply insight stream refinements (parallax, shadows)
 46. Add satellite node breathing animations

 Phase 10: Calendar Migration

 47. Identify existing calendar views to deprecate
 48. Migrate calendar route to redirect to Plannerum
 49. Update voice commands to use "Plannerum" terminology
 50. Remove or hide deprecated calendar UI
 51. Ensure posting calendar remains functional (if separate)

 Phase 11: Integration & Polish

 52. Plannerum ↔ XP system integration
 53. Voice command additions ("Open Plannerum", etc.)
 54. Keyboard shortcuts (P for Plannerum, T for Thinkspace)
 55. Empty states for all Plannerum views
 56. Responsive layout adjustments
 57. Performance testing (especially transitions)
 58. Animation timing refinement

 ---
 PART 10: FILE IMPACT SUMMARY

 Files to MODIFY

 Navigation & Entry:
 - Navigation/MainView.swift - Change entry point to Sanctuary, add Plannerum/Thinkspace
 routing
 - Core/CosmoApp.swift - Potentially update default navigation section

 Sanctuary Core:
 - UI/Sanctuary/SanctuaryView.swift - Add satellite nodes container, connection threads
 - UI/Sanctuary/SanctuaryHeroOrb.swift - Polish: inner glow, particles, orbital ring
 - UI/Sanctuary/DimensionOrbView.swift - Polish: halo glow, hover lift effect
 - UI/Sanctuary/SanctuaryTokens.swift - Add satellite colors, new spring definitions
 - UI/Sanctuary/SanctuaryAnimationChoreographer.swift - Add satellite entry animations

 Existing Data Models (Integration):
 - Data/Models/InboxViewBlock.swift - Ensure compatible with Plannerum inbox rail
 - Data/Models/Atom.swift - Verify scheduleBlock type has all needed properties

 Files to CREATE

 Sanctuary Additions:
 - UI/Sanctuary/SatelliteNodeView.swift - Reusable satellite orb (72pt, configurable
 color/icon)
 - UI/Sanctuary/SanctuaryConnectionThread.swift - Curved bezier with glow animation

 Plannerum (New Directory: UI/Plannerum/):
 - PlannerumView.swift - Main container with view mode state
 - PlannerumTokens.swift - Design tokens (colors, springs, spacing)
 - InboxRailView.swift - Left panel inbox streams container
 - InboxStreamRow.swift - Individual inbox entry with count badge
 - DayTimelineView.swift - Vertical time ribbon (Day view)
 - TimeBlockCard.swift - Glass card for scheduled blocks
 - WeekArcView.swift - Constellation-style week view
 - DayOrb.swift - Day representation with density glow
 - MonthDensityView.swift - Heat map month view
 - ActiveFocusBar.swift - Bottom dock with timer
 - BlockCreationSheet.swift - Modal for creating/editing time blocks

 Files to DEPRECATE/MIGRATE

 Existing Calendar (to be replaced):
 - Identify all calendar-related views in codebase
 - Route calendar navigation to Plannerum
 - Keep posting calendar if it's a separate concern

 Files UNCHANGED

 Preserved Systems:
 - Canvas/CanvasView.swift - Thinkspace uses existing (only transition changes)
 - UI/Sanctuary/SanctuaryBackgroundView.swift - Mist/fog preserved exactly
 - UI/Sanctuary/SanctuaryMetalRenderer.swift - Aurora shader preserved
 - UI/Sanctuary/SanctuaryShaders.metal - No changes
 - All dimension detail views (Dimensions/*/) - No changes
 - Data/Models/LevelSystem/* - XP system unchanged (just integration points)
 - AI/BigBrain/* - Intelligence engines unchanged

 ---
 APPENDIX A: VISUAL REFERENCE NOTES

 From Destiny World Map (Inspiration Points):

 - Planetary orbs with distinct visual identity
 - Subtle glowing connection lines
 - Depth through blur and scale
 - Clean labeling beneath nodes
 - Ambient mystery through darkness and glow
 - Notification indicators on nodes (!)

 From Current Sanctuary (Preserve Points):

 - Hexagonal constellation layout
 - Mist/fog atmospheric depth
 - Typography hierarchy (SANCTUARY header)
 - Level badge with XP bar
 - Dimension color coding
 - Insight stream carousel

 COSMO Identity (Maintain):

 - Elevated, not gritty
 - Mythic, not military
 - Professional transcendence
 - Soft fog, not heavy texture
 - Neon-subtle, not neon-loud
 - Spiritual warrior aesthetic

 ---
 End of Architectural Brief