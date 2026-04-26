# Cosmo Design Language v1.1

## The North Star

Cosmo is not a productivity app.

Cosmo is a **dark observatory for the mind**.

It should feel like a calm, spatial, intelligent environment where thoughts become objects, objects become constellations, and constellations become action.

The UI should make the user feel:

> “I can think here. I know where everything is. I am in control.”

Cosmo must feel like a sanctuary, not a dashboard.

It should combine:

- **Raycast-level command precision**
- **Linear-level hierarchy and restraint**
- **Arc-level sense of space and personal environment**
- **Muse-level creative calm**
- **MyMind-level object beauty**
- **Craft-level writing surfaces**
- **Heptabase-level spatial thinking**
- **Apple-level depth, polish, and quiet confidence**

But Cosmo should not look copied from any of them.

Cosmo’s identity is darker, more spatial, more philosophical, more alive.

The design should feel like:

> Linear’s discipline + Raycast’s speed + Muse’s calm + MyMind’s memory beauty + Heptabase’s spatial knowledge + Apple’s spatial depth, wrapped in a cosmic cognitive OS.

---

# 1. Design Philosophy

## 1.1 Cosmo’s core visual metaphor

Cosmo is a **dark observatory for cognition**.

This metaphor should guide every screen.

A good Cosmo UI feels like:

- a quiet observatory
- a premium instrument panel
- a spatial map of the user’s mind
- a creative sanctuary
- a command cockpit
- a living archive

A bad Cosmo UI feels like:

- a generic SaaS dashboard
- a dark Notion clone
- a Figma board with prettier colors
- a task manager with glassmorphism
- a pile of panels and cards
- AI slop with glows and gradients

The UI should never scream.

It should whisper with precision.

---

## 1.2 The emotional standard

Every major screen should pass this emotional test:

> “Does this make me feel more lucid?”

Not just more productive.

More lucid.

The UI should reduce mental friction, create orientation, and invite deep work.

The feeling should be:

- calm
- clean
- spacious
- sacred
- responsive
- alive
- powerful underneath
- simple on top

---

## 1.3 Cosmo’s sacred promise

Every visual decision should support this promise:

> **Every thought has a home.**

This means:

- captured thoughts should feel valuable
- objects should feel embodied
- canvases should feel navigable
- search should feel instant and trustworthy
- references should feel alive
- actions should feel obvious
- nothing should feel lost

---

# 2. Universal Design Laws

These laws must be followed across the entire product.

## Law 1: Fewer surfaces, stronger hierarchy

Do not solve hierarchy by adding more boxes.

Use this order first:

1. spacing
2. typography
3. alignment
4. opacity
5. subtle dividers
6. surface changes
7. borders
8. color accents
9. glow

If a screen needs many boxes to make sense, the information architecture is probably wrong.

---

## Law 2: One clear focal point per screen

Every screen must have one dominant object, area, or action.

Examples:

- CMD+K: the search input and selected result
- Inbox: the selected capture / active soft cluster
- Canvas: the selected object or cluster
- Document: the writing body
- Object panel: the object identity and recommended action

Everything else should recede.

A UI where everything has equal visual weight is not premium.

---

## Law 3: Quiet by default, alive on interaction

Unselected elements should be calm.

Selected, hovered, dragged, or recommended elements should become alive.

This creates contrast.

Cosmo should not be glowing everywhere.

Glow is sacred.

Use glow only for:

- active selection
- route previews
- confirmed placement
- AI recommendation focus
- current command state
- drag/drop target
- active session/focus state

---

## Law 4: Color is semantic, not decorative

Colors must communicate meaning.

Do not use random colors to “make it look nice.”

Color should indicate:

- state
- type
- confidence
- action
- domain
- relationship
- progress

The user should learn the language subconsciously.

---

## Law 5: Depth must be functional

Glass, blur, and shadows are allowed only when they clarify layers.

Use depth for:

- command menus
- overlays
- inspectors
- floating toolbars
- modals
- selected object focus
- canvas objects above background

Do not use glass for every base surface.

Base surfaces should usually be matte.

Floating surfaces can be glass.

---

## Law 6: The canvas is the world, not the UI

On spatial screens, the canvas should feel like an environment.

Chrome should be minimal.

Controls should float quietly.

Objects should feel placed, not listed.

The user should feel like they are moving through their mind, not manipulating a diagramming tool.

---

## Law 7: Commands should feel inevitable

Every command surface should answer:

- What can I do here?
- What is selected?
- What happens if I press Enter?
- What are my secondary actions?
- How do I escape?

Raycast is the reference for this level of clarity.

---

## Law 8: AI must feel like intelligence, not decoration

Do not represent AI with generic sparkles everywhere.

AI should appear as:

- recommendations
- explanations
- route previews
- related object suggestions
- destination previews
- object summaries
- next actions
- confidence levels

AI should make the system feel more trustworthy, not more magical in a vague way.

---

## Law 9: Every object must have identity

Every object card/block should clearly communicate:

- what it is
- what type it is
- where it belongs
- why it matters
- what state it is in
- what can happen next

This is especially important for:

- notes
- swipes
- sources
- connections
- mental models
- content drafts
- tasks
- captures

---

## Law 10: The UI should disappear during flow

When the user is writing, thinking, arranging, or searching, unnecessary UI should fade into the background.

The product should feel powerful before and after the action, but nearly invisible during the action.

---

# 3. The Cosmo Visual Grammar

## 3.1 Theme-aware design

Cosmo supports themes.

Therefore, never hardcode colors directly in components.

Use semantic tokens.

Components should reference roles, not colors.

Bad:

```ts
background: '#0B1017'
color: '#4EF5A2'
```

Good:

```ts
background: 'var(--surface-primary)'
color: 'var(--accent-primary)'
```

Every theme must define the same semantic roles.

---

## 3.2 Semantic color roles

Use these roles across themes:

```ts
--bg-root
--bg-canvas
--bg-elevated
--bg-overlay

--surface-0
--surface-1
--surface-2
--surface-3
--surface-hover
--surface-active
--surface-selected

--border-subtle
--border-default
--border-strong
--border-selected

--text-primary
--text-secondary
--text-muted
--text-faint
--text-inverse

--accent-primary
--accent-primary-soft
--accent-primary-strong

--accent-secondary
--accent-secondary-soft
--accent-secondary-strong

--state-success
--state-warning
--state-danger
--state-info

--type-note
--type-content
--type-source
--type-connection
--type-task
--type-swipe
--type-database

--confidence-high
--confidence-medium
--confidence-low

--shadow-soft
--shadow-floating
--shadow-command

--blur-overlay
--blur-panel
```

---

## 3.3 Default dark cosmic theme

The current Cosmo visual world is dark, green/purple accented, spatial, and cosmic.

Default theme direction:

```css
--bg-root: #05070B;
--bg-canvas: #070A0F;
--bg-elevated: #0B1017;
--bg-overlay: rgba(13, 16, 22, 0.84);

--surface-0: rgba(255,255,255,0.025);
--surface-1: rgba(255,255,255,0.045);
--surface-2: rgba(255,255,255,0.065);
--surface-3: rgba(255,255,255,0.085);
--surface-hover: rgba(255,255,255,0.075);
--surface-active: rgba(78,245,162,0.10);
--surface-selected: rgba(78,245,162,0.13);

--border-subtle: rgba(255,255,255,0.055);
--border-default: rgba(255,255,255,0.085);
--border-strong: rgba(255,255,255,0.14);
--border-selected: rgba(78,245,162,0.52);

--text-primary: #E8EEF6;
--text-secondary: #A2ADBA;
--text-muted: #727D8C;
--text-faint: #4B5563;
--text-inverse: #07100C;

--accent-primary: #4EF5A2;
--accent-primary-soft: rgba(78,245,162,0.14);
--accent-primary-strong: #7CFFC0;

--accent-secondary: #9B6DFF;
--accent-secondary-soft: rgba(155,109,255,0.16);
--accent-secondary-strong: #BFA5FF;

--state-success: #4EF5A2;
--state-warning: #F6B94B;
--state-danger: #FF5C66;
--state-info: #67A7FF;

--shadow-soft: 0 10px 34px rgba(0,0,0,0.25);
--shadow-floating: 0 18px 70px rgba(0,0,0,0.45);
--shadow-command: 0 24px 90px rgba(0,0,0,0.58);

--blur-overlay: 18px;
--blur-panel: 24px;
```

These are reference values, not hardcoded rules.

All implementation should use theme tokens.

---

# 4. Spatial Atmosphere

## 4.1 Backgrounds

The background should feel like deep space, not a decorative wallpaper.

Use:

- near-black base
- extremely subtle grid
- subtle star/noise texture
- faint gradients only when they create depth
- no busy patterns behind text

Canvas background rules:

```txt
- Grid opacity: extremely low
- Stars/dots: sparse and subtle
- Gradients: slow, broad, barely visible
- No high-contrast background shapes behind primary work
- Background must never compete with objects
```

The canvas should be felt more than seen.

---

## 4.2 Surfaces

There are three major surface classes.

### Matte surfaces

Used for:

- base panels
- cards
- rows
- sidebars
- document blocks

Feel:

- calm
- stable
- grounded

### Glass surfaces

Used for:

- CMD+K
- search overlays
- floating inspectors
- command palettes
- modals
- destination previews
- toolbars

Feel:

- floating
- layered
- OS-like

### Focus surfaces

Used for:

- selected cards
- active object panels
- current command result
- recommended placement

Feel:

- alive
- slightly luminous
- precise

---

## 4.3 Depth hierarchy

Depth should communicate layer order.

From lowest to highest:

```txt
1. Root background
2. Canvas grid / spatial field
3. Unselected objects
4. Cluster surfaces
5. Selected objects
6. Side panels / object passports
7. CMD+K / command overlays
8. Modal confirmations
9. Toasts / temporary feedback
```

Do not give the same shadow or border treatment to every layer.

---

# 5. Typography

## 5.1 Typography personality

Cosmo should feel both intelligent and warm.

Use a dual-type system:

- **Serif** for major conceptual titles, reflective surfaces, object names with philosophical weight, and sanctuary moments.
- **Sans** for operations, lists, metadata, controls, command surfaces, dense UI, and anything the user acts on quickly.
- **Mono** only for system codes, keyboard hints, diagnostics, and technical snippets.

This gives Cosmo a ritualistic hierarchy:

- **Serif = soul**
- **Sans = control**
- **Mono = system**

The serif is part of Cosmo’s identity. It gives the app an ancient-library / observatory / philosopher’s-desk feeling. Keep it, but assign it a sacred role.

Typography law:

> **Poetic where the user thinks. Precise where the user acts.**

Use the serif when the user is reading, reflecting, naming, or creating. Avoid it when the user is navigating, filtering, triaging, selecting, or executing.

### Serif usage

Use serif for:

- page titles
- connection titles
- mental model names
- content/document titles
- major empty states
- philosophical prompts
- core idea text
- special sanctuary moments
- selected conceptual object names on canvas, when appropriate

Avoid serif for:

- buttons
- metadata
- task rows
- CMD+K result rows
- database utility labels
- timestamps
- filters
- menus
- form labels
- dense lists
- status badges
- sidebars, except possibly the app mark/logo

The goal is **ritual without cosplay**. Cosmo can feel poetic, but it must never become fantasy UI. Mechanical parts must stay brutally clear.

Every poetic label needs a practical neighbor.

Good:

```txt
THE WELL
Linked Sources

THE FORGE
Goal / Problems / Benefits / References

THE ATELIER
Concept collaborator
```

Bad:

```txt
THE WELL OF ECHOES
Sacred Threads
Astral Anchors
Source Orbs
```

Keep the metaphysics underneath. Keep the interface lucid.

---

## 5.2 Type scale

Use a consistent type scale.

```txt
Display:       40-48px / 1.05 / serif
Page title:    30-36px / 1.1  / serif or sans depending screen
Section title: 13-15px / 1.2  / sans uppercase/tracked
Object title:  16-20px / 1.25 / sans or serif depending object
Body:          14-16px / 1.55 / sans
Metadata:      12-13px / 1.3  / sans
Microcopy:     11-12px / 1.2  / sans, muted
Keyboard:      11-12px / 1.0  / mono/sans
```

---

## 5.3 Text hierarchy rules

Primary text:

- high contrast
- used sparingly
- object titles, page titles, current values

Secondary text:

- summaries
- helper text
- metadata with importance

Muted text:

- timestamps
- inactive states
- counts
- labels

Faint text:

- background hints
- placeholders
- disabled controls

Never make metadata compete with object titles.

---

## 5.4 Section labels

Cosmo section labels should be small, uppercase, tracked, and quiet.

Example:

```txt
CONTEXT
REFERENCE OUTLINE
DESTINATION PREVIEW
NEARBY OBJECTS
```

Style:

```css
font-size: 11px;
letter-spacing: 0.16em;
font-weight: 700;
text-transform: uppercase;
color: var(--accent-primary);
opacity: 0.72;
```

Do not overuse section labels. Too many makes the UI feel like a form.

---

# 6. Spacing System

## 6.1 Base spacing scale

Use a strict 4px scale.

```txt
2px  = hairline nudges
4px  = micro gaps
8px  = tight internal gaps
12px = compact groups
16px = card padding / row groups
20px = panel internal rhythm
24px = section gaps
32px = major layout gaps
40px = page-level breathing
48px = sanctuary spacing
64px = large canvas/document rhythm
```

---

## 6.2 Page spacing

```txt
Main page padding: 24-32px
Wide canvas chrome: 16-24px
Document max width: 720-860px
Command overlay width: 760-980px depending mode
Sidebar width: 240-300px
Inspector width: 320-420px
```

---

## 6.3 Premium spacing rule

Most AI-generated UI fails because spacing is inconsistent.

Use these rules:

- related items close together
- separate ideas with meaningful gaps
- avoid random margins
- cards should breathe outside and be efficient inside
- rows should be compact but not cramped
- panels should have generous outer padding
- dense UI needs stronger alignment

---

# 7. Radius, Borders, Shadows, Blur

## 7.1 Radius scale

```txt
Small controls: 8-10px
Buttons: 10-14px
Cards: 14-20px
Panels: 20-28px
Command overlays: 20-28px
Canvas clusters: 18-26px
Circular controls: full radius
```

Use larger radius for floating spatial objects and smaller radius for utility controls.

---

## 7.2 Borders

Borders should be low contrast.

Default border:

```css
1px solid var(--border-default)
```

Subtle divider:

```css
1px solid var(--border-subtle)
```

Selected border:

```css
1px solid var(--border-selected)
```

Avoid:

- thick borders
- multiple nested borders
- high-contrast outlines on inactive elements
- border-heavy layouts

---

## 7.3 Shadows

Use shadows only for layered/floating elements.

Base cards should often have no visible shadow.

Floating overlays should have strong but soft depth.

```css
box-shadow: var(--shadow-floating);
```

Do not put dramatic shadows on every card.

---

## 7.4 Blur

Blur is for glass overlays, not everything.

Allowed:

- command palette
- modal
- object inspector
- floating toolbar
- destination preview

Avoid:

- blur behind every card
- blur on dense text containers
- blur that reduces readability

---

# 8. Interaction States

Every interactive element must have these states:

- default
- hover
- active/pressed
- focused keyboard state
- selected
- disabled
- loading/processing

## 8.1 Hover

Hover should be subtle.

Examples:

- background becomes `surface-hover`
- text moves from muted to secondary/primary
- border slightly strengthens
- hidden actions fade in

No big jumps.

---

## 8.2 Selected

Selected state should be beautiful.

Selected means:

- slightly brighter surface
- accent border or accent top line
- maybe soft glow
- visible contextual actions
- related objects/lines subtly activate

Selected should feel like the object has “woken up.”

---

## 8.3 Focus state

Keyboard focus must be visible but elegant.

Use:

```css
outline: 1px solid var(--accent-primary);
outline-offset: 2px;
box-shadow: 0 0 0 4px var(--accent-primary-soft);
```

But tune to the component.

---

## 8.4 Loading state

Loading should feel calm and intelligent.

Bad:

- generic spinner everywhere
- skeletons that flash loudly
- full screen blocking

Good:

- subtle shimmer
- “Finding possible homes…”
- small animated dots
- progressive AI status
- optimistic layout preserved

---

# 9. Component Language

## 9.1 Buttons

### Primary button

Used for one main action.

Examples:

- Confirm placement
- Place
- Start focus
- Create cluster
- Save

Style:

```txt
- accent fill
- dark/inverse text
- medium weight
- 34-40px height
- 10-14px radius
- no glow by default
- hover slightly brighter
- active scale 0.98
```

Only one primary button per local section.

---

### Secondary button

Used for supportive actions.

Style:

```txt
- transparent or surface-1 background
- subtle border
- muted/secondary text
- hover surface-hover
- no glow
```

---

### Ghost button

Used for quiet utility.

Style:

```txt
- no background by default
- muted text/icon
- hover surface-hover
- compact
```

---

### Danger button

Danger should be clear but not huge.

Use red only for destructive action.

Destructive action should usually live lower in the hierarchy or behind confirmation.

---

## 9.2 Icon buttons

Icon buttons should be consistent.

```txt
Small: 28-32px
Default: 36-40px
Large radial/action: 44-52px
```

Rules:

- icons must be optically centered
- inactive icons muted
- active icons use semantic accent
- hover background subtle
- tooltip for ambiguous icons

---

## 9.3 Cards

Cards are knowledge objects, not decoration.

### Standard object card

```txt
┌─────────────────────────────┐
│ Type / state         meta   │
│                             │
│ Object title                │
│ Short essence / preview     │
│                             │
│ Context / route / usage     │
└─────────────────────────────┘
```

Rules:

- title first, metadata second
- at most 1-2 visible badges
- one accent treatment max
- no random icons
- no unnecessary nested boxes
- selected state should be richer than default

---

### Precious object card

For visual databases, swipes, sources, captures, books, media.

Inspired by MyMind.

Rules:

- object preview should be visually dominant
- metadata should be quiet
- card should feel collectible
- grid should feel curated, not mechanical
- avoid too many borders
- use masonry or varied card proportions where useful

---

## 9.4 Panels

Panels are for context, not clutter.

### Inspector panel

Used for object passport, recommendation detail, side metadata.

Rules:

- width: 320-420px
- large radius if floating
- glass or elevated matte
- sections clearly separated
- one primary action visible
- utility actions lower or inside overflow

The first visible area should answer:

1. What is this?
2. Why does it matter?
3. What should happen next?

Not:

1. Here are 9 buttons.

---

### Floating panel

Used for command menus, search, previews.

Rules:

- high depth
- strong focus
- blurred background allowed
- border subtle but present
- bottom action bar allowed
- should feel OS-native

---

## 9.5 Toolbars

Toolbars should be quiet and compact.

Use:

- icon-first controls
- tooltip labels
- selected state obvious
- group related tools
- avoid permanent labels unless necessary

Canvas toolbar should feel like an instrument tray, not a SaaS toolbar.

---

## 9.6 Badges and pills

Badges should be meaningful.

Types:

- object type
- state
- confidence
- source
- route
- count

Rules:

- no more than 2-3 badges per card
- muted by default
- accent only when state matters
- avoid colorful badge soup

---

## 9.7 Toasts

Toasts should be small, calm, and useful.

Example:

```txt
Placed in Philosophy → GOD
Undo · Open
```

Rules:

- bottom or lower-center
- glass/matte floating surface
- short message
- one or two actions
- auto-dismiss after 4-6 seconds

---

# 10. Command/Search Design Language

References: Raycast-style command menus, emoji picker, calculator, clipboard history.

This includes:

- CMD+K
- database search
- command sections
- global search
- object routing
- action menus
- right-click search/bring from DB

## 10.1 Command surfaces are the nervous system

CMD+K should feel like the fastest way to operate the entire mind.

It should feel:

- instant
- focused
- deep
- keyboard-native
- spatially aware
- visually calm

The user should feel like:

> “I can reach anything from here.”

---

## 10.2 Command overlay structure

Default structure:

```txt
┌───────────────────────────────────────────────────────────────┐
│  Search / command input                            mode / Tab │
├───────────────────────────────────────────────────────────────┤
│ Section label                                                  │
│ ┌ Result row / preview card ┐                                  │
│ ┌ Result row / preview card ┐                                  │
│ ┌ Result row / preview card ┐                                  │
│                                                               │
├───────────────────────────────────────────────────────────────┤
│ Current context                         Enter Open · ⌘K Actions│
└───────────────────────────────────────────────────────────────┘
```

For visual results, use Raycast-style grids.

For object/database search, use either:

- left results + right preview
- grid cards + detail on selection
- grouped results by type/domain

---

## 10.3 Command overlay style

Rules:

- centered or contextually anchored
- width 760-980px
- large radius 22-28px
- glass overlay
- border subtle but crisp
- high shadow depth
- background dim optional
- input is visually dominant
- selected result clearly highlighted
- bottom action bar always predictable

---

## 10.4 Command input

Input should feel like a thought portal.

Rules:

- large enough to breathe
- icon optional
- placeholder specific to mode
- no heavy boxed input inside boxed overlay unless needed
- use vertical rhythm like Raycast

Examples:

```txt
Search your mind...
Bring something here...
Place selected object...
Search swipes...
Ask Cosmo...
```

---

## 10.5 Command result rows

Rows should include:

- icon/type marker
- title
- secondary metadata
- location/state
- optional right-side action/type label

Example:

```txt
[connection icon] Untouchable                 Philosophy → Identity
Mental model · 3 insights                     Connection
```

Rules:

- selected row has stronger background
- title primary
- metadata muted
- right-side command label muted
- avoid too many pills

---

## 10.6 Command visual grids

For emoji, swipes, images, database cards, clipboard-style history:

Rules:

- grid cells should be tactile
- selected cell has clear outline/glow
- cells quiet by default
- preview/details appear on side or below
- bottom action bar remains stable

---

## 10.7 Bottom action bar

Inspired by Raycast.

Every command overlay should have a stable bottom action bar.

It should show:

- current mode/source
- primary action
- Enter hint
- secondary actions
- shortcut hint

Example:

```txt
Database Search              Open Object ↵   |   Actions ⌘K
```

Or:

```txt
Inbox Capture                Place ↵         |   Change Route ⌘K
```

This makes command surfaces feel controllable.

---

## 10.8 Command modes

CMD+K should support modes:

- Search
- Create
- Bring from DB
- Place
- Link
- Transform
- Ask Cosmo
- Navigate
- Actions

Mode switching should be visible but quiet.

---

## 10.9 Spatial awareness in search

Search results should show location state.

Examples:

```txt
Home: Philosophy → GOD
Inbox → awaiting placement
Appears in: Personal Brand, Life
Used in: Ben carousel draft
```

Right-click / actions:

- Open
- Go to object
- Show appearances
- Add to current canvas
- Place in...
- Link to selected
- Transform into content

This is core to Cosmo.

---

# 11. Sidebar and Secondary Menu Design Language

References: Arc/Linear-style sidebars and secondary menus.

Sidebars are not the star.

They are the quiet home base.

## 11.1 Sidebar purpose

Sidebars should provide:

- orientation
- navigation
- context switching
- lightweight counts
- persistent identity

They should not become cluttered control panels.

---

## 11.2 Sidebar visual style

Rules:

- matte dark surface
- subtle separation from main content
- no heavy card borders everywhere
- active item clearly selected
- icons muted but readable
- groups collapsible
- counts small and quiet
- user/account area low and grounded

---

## 11.3 Sidebar structure

Recommended structure:

```txt
Global search / quick jump

Primary zones
- Command Center
- Inbox
- Codex / Library

Thinkspaces
- All
- AI
- Ben
- Josh
- Life
- Philosophy

Utility / account
```

Use section headers sparingly.

---

## 11.4 Active item

Active sidebar item should have:

- slightly brighter surface
- accent left dot/bar or subtle pill
- text primary
- icon accent or stronger contrast

Do not use huge bright fills.

---

## 11.5 Secondary menus

Secondary menus should feel like Raycast/Linear context panels.

Rules:

- compact rows
- icons optional
- selected row clear
- keyboard navigable
- destructive actions separated
- related actions grouped

---

# 12. Document and Writing Surface Design Language

References: Craft-like documents, Muse-like cards, clean writing surfaces.

Documents in Cosmo must feel calm, premium, and serious.

The writing surface should feel like a desk.

Not a form.

Not a CMS.

Not a notes app clone.

## 12.1 Document emotional target

The user should feel:

> “I can write something meaningful here.”

Document surfaces should be:

- spacious
- typographically beautiful
- low chrome
- structured only when useful
- distraction-free but context-rich

---

## 12.2 Document layout

Recommended layout:

```txt
┌──────────────┐ ┌──────────────────────────────┐ ┌──────────────┐
│ Outline      │ │ Main writing surface          │ │ Context      │
│              │ │                              │ │ Source       │
│ Sections     │ │ Title                         │ │ Blueprint    │
│ Core idea    │ │ Body                          │ │ Brand        │
│              │ │                              │ │ Cosmo        │
└──────────────┘ └──────────────────────────────┘ └──────────────┘
```

But sidebars should be collapsible.

Main writing body always wins.

---

## 12.3 Document body

Rules:

- max width 720-860px
- generous line height
- strong title hierarchy
- soft metadata under title
- section gaps substantial
- body text highly readable
- inline commands subtle

Avoid:

- too many side panels open by default
- heavy boxes around paragraphs
- cramped line lengths
- random badges in writing body

---

## 12.4 Document typography

For reflective/longform docs:

- title can use serif
- body can use sans or serif depending theme
- metadata muted italic or small sans
- section headers simple

For content scripts/threads:

- sans body
- slide labels compact
- strong rhythm
- clear separation between slides

---

## 12.5 Highlights, references, and source blocks

Inspired by document apps and reading tools.

Rules:

- highlights should be soft, not neon
- references should be compact cards
- source blocks should show provenance
- inline backlinks should be readable and calm

Example:

```txt
Source: Alan Watts — Trust the universe
Used as: supporting philosophy
```

---

## 12.6 Right-side document context

The right sidebar should expose:

- Source
- Blueprint
- Brand
- Related objects
- Lineage
- Evidence
- Cosmo suggestions

But it should not overwhelm.

Default collapsed groups:

```txt
SOURCE
BLUEPRINT
BRAND
LINEAGE
COSMO
```

The most relevant group may auto-open depending on document state.

---

# 13. Thinkspace / Canvas Design Language

References: Heptabase, Muse, Cosmo’s current canvas language.

Thinkspaces are the heart of Cosmo.

They should feel like spatial rooms for thought.

## 13.1 Thinkspace purpose

A thinkspace is where objects become relationships.

It should support:

- sensemaking
- grouping
- clustering
- exploration
- arrangement
- routing
- synthesis
- creative play

---

## 13.2 Canvas atmosphere

Canvas should feel:

- deep
- calm
- infinite but not empty
- structured but not rigid
- tactile
- alive

The user should feel like:

> “I am walking through my own intelligence.”

---

## 13.3 Canvas controls

Controls should be minimal and floating.

Top/right toolbar:

- select
- link
- shape/cluster
- text/sticky
- draw
- search

Bottom/right:

- zoom
- minimap
- current selection count

Left sidebar optional/collapsible.

Canvas controls should never dominate.

---

## 13.4 Object blocks

Object blocks should feel like living knowledge units.

For Connection/Mental Model blocks, preserve the strong structure:

- title
- type
- maturity/progress
- section grid
- insight count
- drag/drop affordance

Improve with:

- clearer micro-labels
- hover tooltips
- output/usage count
- selected state
- relationship indicators

---

## 13.5 Cluster design

Clusters should be first-class spatial objects.

A cluster should show:

- name
- type/topic
- object count
- summary/essence on hover
- health/maturity maybe
- actions: open, place here, summarize, create from cluster

Visual style:

- faint boundary
- subtle tinted background
- label anchored top-left
- selected cluster boundary stronger

Avoid making clusters look like heavy rectangles.

They should feel like fields of gravity.

---

## 13.6 Lines and relationships

Lines should have meaning.

Relationship types:

- supports
- contradicts
- inspired
- became
- example of
- related to
- source for
- expands
- belongs to

Rules:

- default lines extremely subtle
- selected object reveals related lines
- relationship label appears on hover/selection
- strong lines only for active route/selected relationship

This turns the canvas from pretty to intelligent.

---

## 13.7 Right-click radial menu

Your current right-click empty-space creation is a major strength.

It should become a signature interaction.

The radial menu should feel tactile and OS-like.

Default options:

- Note
- Content
- Connection
- Sticky
- Database
- Template

Context-aware options:

- Add related source
- Bring from DB
- Create cluster here
- Ask Cosmo about this area
- Place inbox item here
- Generate content from selection

Rules:

- large enough targets
- labels clear
- center close button
- subtle glow on hovered item
- no clutter

This interaction should feel like summoning a thought object into the world.

---

## 13.8 Minimap

The minimap should not just be navigation.

It should become semantic radar.

Show:

- current viewport
- major clusters
- selected object
- route destination
- orphaned objects
- high-density zones
- active project areas

But keep it extremely subtle.

---

# 14. Inbox V2 Design Language

The Inbox is not a list.

The Inbox is a spatial staging field.

It is where captured thoughts wait for a home.

## 14.1 Inbox emotional target

The Inbox should feel like:

> “Here is the shape of my recent mind.”

Not:

> “Here are chores I need to process.”

---

## 14.2 Inbox layout

Default: canvas view.

Secondary: list view.

Inbox canvas includes:

- capture bar
- soft clusters
- untriaged item cards
- recommendation panel
- destination preview/minimap
- batch actions

---

## 14.3 Soft clusters

Examples:

```txt
Ready to place
Possible merges
New patterns forming
Needs judgment
```

Destination-specific clusters:

```txt
Place → Philosophy / GOD
Merge → Reinvent Your Life
New → Trust-based cognition
```

Visual style:

- faint boundary
- label + count
- confidence summary
- batch action on hover

---

## 14.4 Inbox item card

Example:

```txt
PLACE · High
“Ask and it will be given to you…”
Route → Philosophy / GOD
3 nearby matches
```

Rules:

- action badge prominent
- content preview readable
- route visible
- confidence visible but subtle
- selected card activates route preview

---

## 14.5 Destination preview

When selecting an Inbox item, show:

- target canvas
- target cluster
- landing point
- nearby objects
- why recommendation exists
- confidence

This preview is crucial.

It transforms AI from “trust me” into “look, here’s why.”

---

# 15. Database / Object Library Design Language

The database should not feel like a file dump.

It should feel like a library of living objects.

## 15.1 Database views

Support multiple views:

- grid
- list
- type groups
- recent
- source
- project/domain
- unplaced
- used in output

---

## 15.2 Visual object grid

Inspired by MyMind.

Rules:

- cards may have varied proportions
- images/swipes/books should be visual
- text notes should be typographic cards
- source cards should show provenance
- content cards should show status/output state

The grid should feel curated, not database-y.

---

## 15.3 Object hover actions

On hover:

- Open
- Go to object
- Add to current canvas
- Link
- Ask Cosmo

Do not show all actions by default.

---

## 15.4 Object location indicator

Every object should show location state somewhere:

```txt
Home: Philosophy → GOD
Inbox: awaiting triage
Appears in 3 places
Used in 2 drafts
```

This is core to the promise that nothing is lost.

---

# 16. Object Passport / Detail Panel

The object panel should feel like a living profile.

It should answer:

1. What is this?
2. What role does it play?
3. Where does it belong?
4. What is it connected to?
5. What should happen next?

## 16.1 Recommended structure

```txt
Object identity
Essence / why this matters
Primary action / suggested next move
Context / home / appearances
References / referenced by
Lineage / used in
Metadata
Utility actions
```

The current panel is close, but top actions should not overpower meaning.

---

## 16.2 Action hierarchy

Show:

- 1 primary recommended action
- 2-3 secondary actions
- rest inside overflow

Avoid button grids with equal weight unless in an explicit action mode.

---

## 16.3 Context section

Context should distinguish:

- Home
- Current thinkspace
- Appears in
- Used in
- Inbox history

This makes object placement feel precise.

---

# 17. Motion Design

Motion should be quiet, meaningful, and physical.

## 17.1 Motion principles

Use motion to show:

- placement
- selection
- navigation
- layer changes
- object creation
- command execution
- successful completion

Do not use motion as decoration.

---

## 17.2 Recommended timings

```txt
Micro hover: 80-120ms
Button press: 80ms
Panel open: 160-220ms
Command overlay: 140-180ms
Canvas pan/zoom: 220-360ms
Placement animation: 300-500ms
Toast: 180ms in / 160ms out
```

Easing:

```txt
ease-out for opening
spring for physical object movement
linear/soft for background transitions
```

---

## 17.3 Placement animation

When an item gets placed:

1. card lifts slightly
2. compresses into a point/diamond
3. faint route line appears
4. item travels/fades toward destination preview
5. toast confirms
6. if Place & Go, canvas opens and object pulses once

This should feel satisfying but not flashy.

---

# 18. Empty States

Empty states should feel emotionally rewarding.

## 18.1 Inbox empty

```txt
Inbox clear.

Every thought has a home.

[Capture a thought] [Open recent placements]
```

## 18.2 Empty canvas

```txt
This thinkspace is quiet.

Right-click anywhere to create, or bring something in from your database.
```

## 18.3 Empty search

```txt
No exact matches.

Search deeper, create new, or ask Cosmo.
```

Empty states should not feel like errors.

They should feel like invitations.

---

# 19. AI UX Patterns

## 19.1 AI recommendation card

Should include:

- recommendation
- confidence
- reason
- alternatives
- action

Example:

```txt
Place in Philosophy → GOD
High confidence

This capture is about prayer, belief, surrender, and receiving before proof. It sits near existing objects about trusting the universe.

[Place] [Change] [Place & Go]
```

---

## 19.2 Confidence display

Confidence should be visible but not too mathematical.

Use:

- High
- Medium
- Low

Show percentages only when useful, such as merges.

---

## 19.3 AI explanations

Good explanations are concrete.

Bad:

```txt
Semantic match score is high.
```

Good:

```txt
This belongs in GOD because it talks about prayer, belief, and surrender, and overlaps with your existing Alan Watts source.
```

---

## 19.4 AI as librarian, cartographer, producer

AI should take three roles:

### Librarian

- names
- types
- routes
- deduplicates
- files

### Cartographer

- clusters
- maps
- connects
- finds spatial homes
- detects orphans

### Producer

- turns objects into output
- creates outlines
- extracts hooks
- strengthens claims

These roles should guide AI UI.

---

# 20. Creative Play Features To Add

These features are inspired by the reference apps but tailored to Cosmo.

## 20.1 Spatial clipboard / capture shelf

Inspired by Raycast clipboard + canvas interaction.

A small floating shelf of recent captures that can be dragged into any canvas.

Use cases:

- drag Telegram capture into thinkspace
- drag screenshot into content draft
- drag swipe into hook cluster
- drag quote into mental model

This makes capture feel physical.

---

## 20.2 Command dock

Inspired by Raycast’s bottom mode selector.

A small context-aware dock that appears in command/search states:

```txt
Database · Cosmo · Emoji · Clipboard · Calculator · Actions
```

For Cosmo:

```txt
Search · Create · Bring · Place · Link · Ask
```

This makes CMD+K feel like an OS utility layer.

---

## 20.3 Visual “Go to object” transitions

When jumping from CMD+K to an object, animate like spatial teleportation:

- fade command menu
- open destination canvas
- pan/zoom to object
- pulse highlight
- show location breadcrumb briefly

This makes search feel spatial, not just textual.

---

## 20.4 Object appearances panel

Every object can appear in multiple places.

Add a panel:

```txt
Appears in:
- Primary: Philosophy → GOD
- Personal Brand → Confidence
- Inbox history
- Ben draft source panel
```

This solves the “where is it?” problem beautifully.

---

## 20.5 Canvas mood modes

Let thinkspaces have a visual mood/theme without hardcoding app-wide colors.

Examples:

- Philosophy: deep purple/green cosmic
- Client Work: sharp emerald/amber cockpit
- Personal Brand: warmer creative studio
- Research: quiet blue/gray archive

This creates emotional context like Arc Spaces.

Must be token-driven.

---

## 20.6 Cluster composer

Select multiple objects and press a command:

```txt
Summarize cluster
Create framework
Turn into content
Find missing references
Create mental model
```

This turns spatial arrangement into output.

---

## 20.7 Semantic radar minimap

Upgrade minimap to show:

- active clusters
- orphaned objects
- dense zones
- recently added items
- currently selected route
- low-confidence placements

This makes the map functional and premium.

---

## 20.8 Beautiful focus mode for any object

Any object can enter focus mode.

The canvas fades.

The object expands.

Related objects orbit subtly or appear in a side rail.

Use for:

- mental models
- content drafts
- source analysis
- connections

This gives a sanctuary/deep-thinking moment.

---

## 20.9 Drag-to-link with relationship chooser

Drag from one object to another.

On drop, show small menu:

```txt
Supports
Inspired by
Became
Example of
Contradicts
Related
```

This makes relationships meaningful without heavy forms.

---

## 20.10 AI “arrange this” command

On any canvas:

```txt
Arrange by concept
Arrange by source
Arrange by output lineage
Arrange by maturity
Arrange by client/project
```

AI proposes arrangement, user accepts.

Never auto-move permanently without confirmation.

---

# 21. Screen-Specific Direction

## 21.1 CMD+K / Search

Reference blend:

- Raycast command palette
- Arc environment switching
- MyMind visual previews

Should feel:

- glassy
- fast
- precise
- OS-native

Must have:

- strong selected result
- stable bottom action bar
- clear input mode
- keyboard hints
- preview when useful
- spatial location metadata

Avoid:

- generic search modal
- too many badges
- huge empty dead space
- hardcoded colors

---

## 21.2 Sidebar

Reference blend:

- Linear sidebar discipline
- Arc spaces personality

Should feel:

- quiet
- grounded
- personal
- instantly navigable

Must have:

- clean active state
- grouped zones
- counts where useful
- collapsible sections
- user identity low in hierarchy

Avoid:

- over-coloring
- too many icons
- nested sidebar chaos

---

## 21.3 Documents

Reference blend:

- Craft writing surfaces
- Muse calm
- Linear side metadata

Should feel:

- focused
- typographic
- premium
- low-friction

Must have:

- strong title
- readable body width
- collapsible context rails
- beautiful source/reference display
- inline commands

Avoid:

- form-like fields
- cramped text
- metadata overpowering writing

---

## 21.4 Thinkspace canvas

Reference blend:

- Heptabase spatial knowledge
- Muse creative calm
- Figma canvas ergonomics
- Cosmo cosmic identity

Should feel:

- spatial
- intelligent
- calm
- alive

Must have:

- clear object selection
- right-click creation
- drag/drop from DB
- relationship lines
- minimap/radar
- cluster surfaces

Avoid:

- generic whiteboard feel
- too many permanent controls
- noisy grids
- over-glowing cards

---

## 21.5 Inbox V2

Reference blend:

- Raycast triage clarity
- Muse spatial table
- MyMind capture beauty
- Apple glass preview

Should feel:

- like thoughts waiting for a home
- spatial, not list-only
- calm, not chore-like
- intelligent, not automatic black box

Must have:

- soft clusters
- recommendation panel
- destination preview
- place/merge/new actions
- canvas/list toggle
- batch actions

---

# 22. Anti-Patterns

Avoid these at all costs.

## 22.1 Card soup

Too many cards nested inside cards.

Fix:

- remove unnecessary containers
- use spacing/dividers
- flatten hierarchy

---

## 22.2 Badge soup

Too many pills/badges/colors.

Fix:

- only show essential state
- move details to hover/panel

---

## 22.3 Glow abuse

Everything glowing makes nothing special.

Fix:

- glow only selected/active/recommended routes

---

## 22.4 Generic SaaS layout

If it looks like a dashboard template, it is wrong.

Fix:

- make it spatial
- make objects feel embodied
- reduce hard panels

---

## 22.5 AI sparkle cliché

Sparkles everywhere cheapen the product.

Fix:

- AI should show through recommendations, explanations, and actions

---

## 22.6 Unclear abbreviations

Compact labels are okay, but not cryptic.

Fix:

- use hover tooltips
- use clearer 3-5 letter labels
- expose meaning in full view

---

## 22.7 Equal-weight actions

Six buttons in a row all looking equally important is bad.

Fix:

- one primary action
- two secondary actions
- rest in overflow

---

## 22.8 Decorative complexity

Complexity must come from capability, not decoration.

Fix:

- remove visuals that do not clarify meaning or action

---

# 23. AI Coding Prompt Template

Use this prompt whenever asking an AI coding agent to build or refactor UI.

```txt
You are working on Cosmo, a dark spatial OS for cognition.

Your task is to improve the UI while preserving the existing product identity and functionality.

Cosmo should feel like a dark observatory for the mind: calm, spatial, premium, lucid, and quietly alive. The UI should make the user feel more creative and in control.

Reference qualities:
- Raycast for command/search precision and bottom action bars.
- Linear for hierarchy, restraint, density, and dark UI discipline.
- Arc for spaces, personal environment, and navigation feel.
- Muse for calm creative canvas energy.
- MyMind for beautiful object grids and capture memory.
- Craft for writing/document surfaces.
- Heptabase for spatial knowledge organization.
- Apple spatial design for depth, restraint, and polish.

Hard rules:
- Use existing theme tokens. Do not hardcode colors.
- Do not add unnecessary containers.
- Do not stack cards inside cards unless essential.
- Do not use decorative gradients or random glow.
- Glow is only for selection, active routes, placement, AI recommendations, or focus states.
- Prefer spacing, typography, alignment, and subtle dividers before adding boxes.
- Every screen must have one clear focal point.
- One primary action per local area.
- Secondary actions should be quiet or hidden in overflow.
- Metadata must be muted and compact.
- Borders must be 1px and low contrast.
- Base surfaces are matte; floating overlays may use glass.
- The canvas background must stay quiet.
- Maintain keyboard accessibility and focus states.

Typography rule:
- Serif = soul. Sans = control. Mono = system.
- Use serif only for meaning-bearing surfaces: major titles, connection/mental-model names, document titles, reflective prompts, and sanctuary moments.
- Do not use serif for navigation, buttons, filters, badges, metadata, sidebars, dense lists, task rows, or command result rows.
- The goal is ritual without cosplay: poetic where the user thinks, precise where the user acts.

Spacing:
- Use a 4px spacing scale.
- Card padding: 14-18px.
- Panel padding: 20-24px.
- Section gaps: 20-28px.
- Page padding: 24-32px.

Interaction:
- Hover states subtle.
- Selected states beautiful and clear.
- Keyboard focus visible.
- Motion meaningful, not decorative.

Before implementing, identify the primary focal point of the UI. Then simplify everything around it.

After implementing, explain:
1. What hierarchy improved.
2. What visual noise was removed.
3. What component rules were followed.
4. How this preserves Cosmo’s design language.
```

---

# 24. UI Review Checklist

Use this after every AI-generated UI change.

## Hierarchy

- Is there one clear focal point?
- Does the selected object stand out?
- Is metadata quieter than primary content?
- Are primary/secondary actions clearly separated?

## Noise

- Can any container be removed?
- Are there too many borders?
- Are there too many badges?
- Are icons adding clarity or noise?
- Does it still look good when squinting?

## Theme consistency

- Are all colors token-based?
- Are accents used semantically?
- Does it work across themes?
- Is contrast accessible?

## Spacing

- Is spacing on a 4px scale?
- Are related items grouped tightly?
- Are different ideas separated clearly?
- Does the screen breathe?

## Interaction

- Are hover states subtle?
- Is focus state visible?
- Is selected state beautiful?
- Are shortcuts shown where useful?
- Does the user know what Enter does?

## Cosmo feeling

- Does it feel like a sanctuary?
- Does it feel spatial?
- Does it feel premium without trying too hard?
- Does it feel like Cosmo, not a generic app?
- Does it make the user feel more lucid?

---

# 25. The Golden Screen Strategy

Do not let AI redesign every screen independently.

Pick one screen and make it the absolute visual benchmark.

Recommended golden screen:

**Inbox V2 canvas with selected item + destination preview.**

Why:

- it includes canvas
- command-like triage
- object cards
- AI recommendation
- detail panel
- minimap
- action buttons
- spatial placement

If this screen is perfect, it defines the whole system.

Every other screen should inherit from it.

Golden screen requirements:

- dark spatial background
- soft clusters
- beautiful object cards
- selected state
- floating inspector
- destination minimap
- bottom/inline actions
- calm typography
- token-perfect surfaces

Once approved, extract its tokens/components into the system.

---

# 26. Implementation Principles For Engineers

## 26.1 Build primitives, not one-off screens

Create reusable primitives:

- Surface
- FloatingPanel
- ObjectCard
- CommandOverlay
- CommandRow
- SearchInput
- SectionLabel
- Badge
- ActionButton
- IconButton
- InspectorPanel
- CanvasCluster
- MiniMap
- Toast
- EmptyState

Every screen should compose these.

---

## 26.2 Components must be theme-aware

Every component uses CSS variables/theme tokens.

No component owns raw colors.

---

## 26.3 Components must have state variants

Every primitive should define:

- default
- hover
- selected
- active
- disabled
- focus
- loading

No ad hoc state styling.

---

## 26.4 Reduce design drift

Before creating a new component, ask:

> Can this be built from an existing primitive?

If yes, reuse.

If no, create a primitive and document it.

---

# 27. Additional Anti-Drift Controls For AI Coding

This section exists because even strong AI systems drift when guidance is abstract. To reduce drift, every substantial UI change should include explicit constraints, reference surfaces, and a review loop.

## 27.1 Required UI task brief

Every UI prompt should include:

```txt
Screen:
What screen/component is being changed?

User goal:
What should the user be able to do faster/easier?

Primary focal point:
What should visually dominate?

Reference section:
Which part of this design language applies?

Do not change:
What functionality/layout must remain?

Allowed changes:
Spacing, hierarchy, selected state, etc.

Forbidden:
Specific anti-patterns to avoid.

Acceptance:
What must be true after the change?
```

## 27.2 Before coding, AI must state the hierarchy

For any UI task, the AI should first state:

```txt
Primary focal point:
Secondary information:
Muted information:
Hidden/overflow actions:
```

If it cannot state this clearly, the UI is not ready to be coded.

## 27.3 Use visual regression screenshots

After implementation:

1. capture screenshot
2. compare to previous
3. run checklist
4. fix obvious drift immediately

The app should not rely on “looks good in code.”

## 27.4 Component snapshot library

Create a small internal route/page showing every primitive:

- buttons
- cards
- badges
- command rows
- panels
- object cards
- document blocks
- canvas clusters
- inbox cards
- toasts
- empty states

This becomes the source of truth for visual consistency.

## 27.5 Golden examples

For every major component category, keep a “golden” approved version.

AI should imitate internal approved components before inventing new styling.

Golden examples needed:

- Command overlay
- Object card
- Canvas mental model block
- Inspector panel
- Document title/body
- Sidebar item
- Inbox triage card
- Destination preview
- Toast

## 27.6 Acceptance tests for theme safety

Every UI change must pass:

- default dark theme
- at least one alternate theme
- hover state
- selected state
- keyboard focus state
- empty state
- long text state
- narrow viewport state, if applicable

## 27.7 Copy/paste prompt add-on for zero-drift tasks

Use this add-on when you want the AI to be extra strict:

```txt
Do not invent a new visual language.
Use existing primitives wherever possible.
If you need a new primitive, define it using existing tokens and explain why it cannot be composed from existing primitives.
Make the UI calmer before making it richer.
Remove at least one source of visual noise if possible.
Do not add glow, gradients, new colors, or new containers unless directly justified by hierarchy.
```

---

# 28. Why This Approach Works

This document works because it gives AI and engineers something more precise than taste.

Most AI UI fails because prompts ask for emotion:

> “Make it premium.”

This document turns taste into constraints:

- visual metaphor
- semantic tokens
- hierarchy rules
- spacing scale
- interaction states
- component behavior
- anti-patterns
- screen-specific direction
- review checklist
- anti-drift workflow

That gives AI fewer ways to go wrong.

It also preserves Cosmo’s uniqueness.

You are not asking AI to copy Linear, Raycast, Muse, MyMind, Craft, Arc, or Heptabase.

You are extracting the strongest design principles from each and fusing them into Cosmo’s own identity.

The result is not “inspired by apps.”

The result is a coherent design operating system.

---

# 29. How To Use This Document

## For every UI task

Give the AI:

1. this design language
2. screenshots of the current screen
3. the specific task
4. the relevant reference apps
5. the anti-patterns to avoid

Example:

```txt
Use the Cosmo Design Language.
This task affects CMD+K, so pay special attention to Section 10.
Preserve functionality.
Make the selected result clearer, reduce container noise, add a Raycast-style bottom action bar, and ensure all styling uses theme tokens.
```

---

## For big redesigns

Use this order:

1. define the focal point
2. remove visual noise
3. apply primitives
4. enforce tokens
5. refine spacing
6. refine selected/focus states
7. add motion last

Do not start with animation, gradients, or glow.

---

## For reviews

Use the checklist in Section 24.

Be ruthless.

If a screen is close but not holy-shit clean, the issue is usually one of these:

- too many equal-weight surfaces
- too much visible chrome
- weak selected state
- inconsistent spacing
- too many badges/buttons
- color used decoratively
- no single focal point

Fix those before adding anything new.

---

# 30. Final Design Mantra

Cosmo should feel like:

> **A sanctuary for thought. A cockpit for creation. A spatial home for the mind.**

Every object has a place.

Every place has meaning.

Every action feels close.

Every screen makes the user more lucid.

That is the standard.
