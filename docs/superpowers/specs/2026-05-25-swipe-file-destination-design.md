# Swipe File Destination Design

## Context

CosmoOS already has a capable swipe system, but its primary browsing surface lives inside Command K. That creates the wrong product posture. Command K should remain the Raycast-grade finder and action layer: fast, temporary, keyboard-first, and excellent for locating or acting on a known object. A swipe file needs a different kind of space. It should be a full-window library for browsing, filtering, studying, and finding patterns across creative references.

The existing codebase gives this project a strong foundation:

- `SwipeFile/SwipeAnalysis.swift` defines `SwipeGalleryItem`, hook types, framework types, emotional metadata, content format, narrative style, engagement counts, and clustering helpers.
- `UI/CommandK/SwipeGalleryCardView.swift` is already the canonical thumbnail card used by Command K, creator profiles, and similar swipe sections.
- `UI/CommandK/SwipeGalleryTab.swift` already has a masonry grid, filtering controls, clustered mode, selection bar, and empty state.
- `UI/CommandK/CommandKViewModel.swift` already loads swipe atoms from `AtomRepository`, converts them via `Atom.toSwipeGalleryItem()`, and memoizes filtered/clustered swipe results.
- `Canvas/UnifiedSidebar/*` and `Navigation/MainView.swift` already provide the global navigation shell where this new destination belongs.

The design should reuse proven data and rendering primitives, but not feel like a copied Command K tab. The full Swipe File surface should feel like something Apple would ship: confident navigation, strong media thumbnails, native Mac density, calm controls, immediate search, precise filtering, smooth browsing, and a premium but restrained material language.

## Product Decision

Build a first-class `Swipe File` destination in the global sidebar. The destination is a full-screen creative reference library inspired by Apple Music's library/browse architecture and Raycast's precision, adapted to CosmoOS's Greenhouse/Cosmo material system.

For this first pass, custom boards are sidebar UI only. They should look real and navigable, but they do not need persistence, board detail screens, drag/drop assignment, or saved membership. The implementation should prepare clean boundaries for boards later without pretending the feature exists.

## The Moment

When the user opens Swipe File, they should feel like their creative memory is no longer a pile of saved posts. It is an organized, beautiful, searchable instrument for finding the exact style, hook, structure, format, or creator they want to study.

## North Star

The best result is not "a larger Command K gallery." The best result is an Apple-grade media library for creative patterns:

- It opens from the sidebar like a primary app section.
- It gives the user an immediate overview of their whole swipe library.
- It turns thumbnails into the dominant visual object.
- It makes filters feel conversational and fast, not database-like.
- It preserves deep study by opening existing Swipe Study focus mode from any card.
- It keeps Command K useful as the fast entry point, while this surface becomes the place to wander, compare, and filter.

## Visual Layout

```text
+------------------------------------------------------------------------------------------------+
| Global Sidebar                  | Swipe File                                                     |
|                                 |                                                              |
| HOME                            |   Swipe File                                      View  Sort  |
|   Home                          |   124 creative references · 18 high-scoring hooks             |
|   Inbox                         |                                                              |
|   Search                        |   +------------------------------------------------------+   |
|                                 |   | Search swipes, creators, hooks, formats, notes...    |   |
| DISCOVER                        |   +------------------------------------------------------+   |
|   Discover                      |                                                              |
|                                 |   [All] [Fear hooks] [Curiosity] [Threads] [Reels]           |
| SWIPE FILE                      |   [High score] [Creator] [Format] [Narrative] [More]          |
|   All Swipes          selected  |                                                              |
|   Recently Added                |   Continue Studying                                           |
|   High Hook Score               |   +----------------+ +----------------+ +----------------+   |
|   Unstudied                     |   | large thumb    | | large thumb    | | quote/text card |   |
|                                 |   | hook label     | | hook label     | | thread hook     |   |
| BOARDS                          |   +----------------+ +----------------+ +----------------+   |
|   + New Board                   |                                                              |
|   Fear Hooks                    |   High-Performing Patterns                                    |
|   Threads                       |   +-----------+ +-----------+ +-----------+ +-----------+      |
|   Launch Ideas                  |   | thumbnail | | thumbnail | | thumbnail | | thumbnail |      |
|                                 |   +-----------+ +-----------+ +-----------+ +-----------+      |
|                                 |                                                              |
|                                 |   All Swipes · 124 results                                    |
|                                 |   +-----------+ +-----------+ +-----------+ +-----------+      |
|                                 |   | masonry   | | masonry   | | tall reel | | text post |      |
|                                 |   | card      | | card      | | card      | | card      |      |
|                                 |   +-----------+ +-----------+ +-----------+ +-----------+      |
+------------------------------------------------------------------------------------------------+
```

The view has four stable regions:

1. **Global Sidebar**
   Primary navigation and board placeholders.
2. **Masthead**
   Title, library stats, search, and high-level view controls.
3. **Shelves**
   Curated horizontal rows that make the library feel alive before the user filters.
4. **Gallery**
   The dense, scrollable workhorse grid for full-library browsing.

## Sidebar Information Architecture

The global sidebar should support the user's requested sections without losing the existing CosmoOS structure.

### Home

Home is the default working area. It should contain:

- `Home` with `house` icon, routing to the current Command Center/home destination unless a future true home screen replaces it.
- `Inbox` with `tray` icon and existing unread badge.
- `Search` with `magnifyingglass`, opening Command K rather than navigating to a separate search screen.

This matches the user's intent: home, commands/inbox, and search belong together.

### Discover

Discover is a first-class sidebar row with a `sparkle.magnifyingglass` or `chart.line.uptrend.xyaxis` style icon. The content can initially be a polished placeholder screen stating that high-performing posts will appear here once the data pipeline is connected. It should not be wired into external scraping or recommendation systems in this pass.

### Swipe File

Swipe File is a first-class sidebar row and destination. It should also have lightweight subrows:

- `All Swipes`
- `Recently Added`
- `High Hook Score`
- `Unstudied`

These subrows set local filters on the same Swipe File destination. They should not create separate screens; the content area remains one premium library surface with the active shelf/filter state reflected in the masthead.

### Custom Boards

Custom Boards are sidebar-only UI in this pass:

- `+ New Board`
- `Fear Hooks`
- `Threads`
- `Launch Ideas`

The rows should look like future user-owned containers. Selecting a board routes to the Swipe File destination and shows a polished board placeholder state in the content area. No persistence, drag/drop, board membership, or board CRUD is required.

## Swipe File Surface

### Masthead

The masthead should behave like Apple Music's library header: large enough to orient, restrained enough to keep content visible.

Required elements:

- Title: `Swipe File`
- Subtitle: dynamic count such as `124 creative references · 18 high-scoring hooks`
- Search field: full-width, prominent, native-feeling, with placeholder `Search swipes, creators, hooks, formats...`
- View controls: compact segmented or icon controls for `Grid`, `Clusters`, and `Compact`
- Sort menu: `Most Recent`, `Oldest First`, `A-Z`, `By Creator`
- Add affordance: a compact `Add Swipe` button that routes through the existing capture flow or opens Command K in capture context

Visual rules:

- The search field should be the first functional object after the title.
- The title should not sit inside a card.
- The controls should use small icon buttons and menus, not large pill labels everywhere.
- The masthead should stay visually anchored while scrolling. The implementation can use a pinned header or a material toolbar-like top band, but the user must never feel lost in a long gallery.

### Filter System

Filters are the core value of this screen. They must support finding "fear-mongering hooks for threads" or "curiosity gap reels from a creator" without turning into a spreadsheet.

Filter categories:

- Platform: YouTube, YT Short, Instagram, X, Threads, Website, Clipboard
- Hook Type: all `SwipeHookType` values
- Framework: all `SwipeFrameworkType` values
- Narrative Style: existing `NarrativeStyle`
- Format: existing `ContentFormat`
- Creator: available creators from loaded swipes
- Niche: available niches from loaded swipes
- Score: high hook score, medium, unrated
- Study state: studied, unstudied
- Engagement: high views, high likes, high comments where metadata exists

Filter UX:

- Show a small set of smart chips by default: `All`, `Fear hooks`, `Curiosity`, `Threads`, `Reels`, `High score`.
- Use menus for the full taxonomy.
- Multi-select should exist for narrative, format, hook type, and framework.
- Active filters should collapse into readable chips with counts where possible.
- Clearing filters should be one click and keyboard reachable.
- Search and filters combine conjunctively: search narrows within the active filter set.

Important taxonomy note:

The current `SwipeHookType` enum does not include a literal `fearMongering` case. The product needs the user-facing filter language "Fear hooks" because that is how the user thinks. The implementation should map `Fear hooks` to a smart preset using existing metadata:

- include `.controversy`
- include `.contrarian`
- include `.boldClaim`
- include swipe text/hook matches for terms such as `mistake`, `warning`, `avoid`, `stop`, `danger`, `before you`, `costing you`, `nobody tells you`, `most people`
- later, a richer taxonomy can add an explicit fear/loss-aversion dimension

This lets the UI satisfy the user's workflow now without requiring a database migration.

### Shelves

Shelves give the screen an Apple Music feeling. They should be horizontal, thumbnail-rich, and curated from the same loaded library.

Initial shelves:

- `Continue Studying`: studied or recently opened swipes if available; otherwise recent high-score swipes.
- `Recently Added`: newest swipes.
- `High-Performing Patterns`: swipes with high hook score or engagement metrics.
- `Hooks to Try`: a rotating/preset row focused on fear, curiosity, contrast, contrarian, and transformation hooks.

Shelf cards should be larger than grid cards, with stronger media presence and concise metadata. The implementation should create a dedicated `SwipeShelfCardView` if the canonical grid card cannot reach the desired Apple-grade composition without awkward branching.

### Gallery

The gallery is the main browsing area.

Modes:

- `Grid`: media-first masonry using platform-aware aspect ratios.
- `Clusters`: existing `buildClusteredSections(from:)`, upgraded visually to feel like grouped library sections rather than nested cards.
- `Compact`: text-forward browsing for threads, X posts, transcripts, and clipboard/raw-note swipes where thumbnail cards are less efficient.

Card behavior:

- Single click selects the card and updates the adaptive detail preview.
- Double click or Return opens Swipe Study focus mode.
- Context menu preserves existing actions: open, add to canvas, delete, copy/open source if available.
- Shift-click multi-select is preserved outside Command K.
- Hover states should be subtle: 1px lift, brighter border, no heavy glow.

Thumbnail behavior:

- Remote thumbnails use existing cached async image behavior.
- Instagram local thumbnail fallback should reuse existing extraction/cache code.
- Text-only swipes need beautiful typographic cards, not blank placeholders.
- Loading thumbnails should show fixed skeletons to prevent layout jumps.
- Failed thumbnails should degrade to platform-colored typographic covers.

### Detail Preview

The full destination should include an adaptive detail preview. On wide windows it appears as a trailing inspector. On narrower windows it becomes a toggleable preview panel or opens as a focused overlay. This gives the surface the Apple Music-like ability to browse without losing context.

The preview shows:

- large thumbnail/media preview
- hook text
- platform/creator/source
- hook type, framework, format, narrative
- engagement metrics
- `Open Study`
- `Use as Blueprint`
- `Add to Board` disabled or marked future until boards are real

Cards still open the existing Swipe Study focus mode for deep teardown. The preview is for fast scanning and deciding whether a swipe is worth opening.

## Visual Direction

The screen should be "Apple Music for creative references," not a SaaS dashboard.

### Material

- Use `DS.bg` for the root content background.
- Use native sidebar material/chrome through existing unified sidebar primitives.
- Use elevated material only for controls, cards, shelf items, and the adaptive inspector.
- Avoid card-in-card nesting.
- Avoid decorative blobs, gradients, and artificial hero art.
- Let real thumbnails provide color and energy.

### Typography

- Masthead title: strong system title, not oversized marketing hero text.
- Section titles: Apple Music-like, bold and direct: `Recently Added`, `High-Performing Patterns`, `All Swipes`.
- Metadata: compact, secondary, monospaced only for scores/counts.
- Cards: hook text should be readable but never crowd the thumbnail.

### Color

- Use semantic `DS` tokens by default.
- Use platform colors only as small badges or subtle thumbnail fallback accents.
- Use `DS.entitySwipe` as the swipe accent.
- Use hook/framework colors as small semantic punctuation.
- Do not let the screen become orange/gold-only, even though swipe currently uses a gold entity color.

### Motion

- Opening the destination: content crossfades and settles with `ProMotionSprings.gentle`.
- Filter changes: grid cards fade/scale from `0.98` with stable layout dimensions.
- Hover: subtle lift/brightness using `ProMotionSprings.hover` or the nearest existing spring.
- Shelf scroll: native horizontal scroll with no custom physics.
- Reduced Motion: disable scale/lift and use opacity changes only.

## Native macOS Behavior

The destination must feel like a real Mac app section:

- Keyboard focus enters the search field when the user starts typing or presses `Command-F`.
- `Escape` clears active search first, then active filters, then selection.
- Arrow keys navigate selected cards where practical.
- Return opens the selected swipe in Swipe Study.
- Toolbar/menu commands can be added later, but the architecture should not block them.
- Right-click context menus must remain available.
- Buttons should be real `Button`/`Menu` controls, not tap gestures.
- Icon-only controls need accessibility labels and help text.

## Data Architecture

The first robust architecture is to extract swipe library state from Command K rather than keep another view dependent on `CommandKViewModel`.

Create a dedicated `SwipeLibraryViewModel` or equivalent store with:

- loading from `AtomRepository.shared.fetchAll(type: .research)` or existing multi-type method
- conversion through `Atom.toSwipeGalleryItem()`
- filter state
- search query
- sort mode
- view mode
- filtered item cache
- clustered section cache
- facet summaries
- shelf derivation
- available creators/niches
- refresh listener for new/deleted swipe notifications

Command K can keep using its current path initially, but the plan should prefer moving shared filtering/loading logic into a reusable non-Command-K type. The full Swipe File destination should not be coupled to Command K presentation state.

Data flow:

```text
AtomRepository
    -> research atoms
    -> Atom.toSwipeGalleryItem()
    -> SwipeLibraryViewModel.items
    -> SwipeLibraryFilterState
    -> filteredItems + clusteredSections + shelves + facets
    -> SwipeFileHomeView
```

Filtering should be performed off the main actor when the library is large, following the current Command K detached-task generation pattern. UI publication must return to the main actor and ignore stale generations.

## Proposed File Boundaries

Create:

- `UI/SwipeFile/SwipeFileHomeView.swift`
  Root destination view. Owns the high-level layout only.
- `UI/SwipeFile/SwipeLibraryViewModel.swift`
  Loads swipes, stores filter/search/view state, produces filtered results and shelves.
- `UI/SwipeFile/SwipeLibraryFilterState.swift`
  Value model for active filters and smart presets.
- `UI/SwipeFile/SwipeLibraryFiltering.swift`
  Pure filtering/sorting/shelf derivation helpers for testability.
- `UI/SwipeFile/SwipeFileMasthead.swift`
  Title, stats, search, view controls.
- `UI/SwipeFile/SwipeFilterBar.swift`
  Smart chips, menus, active filter chips, clear control.
- `UI/SwipeFile/SwipeShelfSection.swift`
  Horizontal Apple Music-style shelves.
- `UI/SwipeFile/SwipeFileGalleryGrid.swift`
  Masonry/grid rendering and selection/opening.
- `UI/SwipeFile/SwipeFileClusteredView.swift`
  Full-window grouped library view using existing clustered sections.
- `UI/SwipeFile/SwipeFileEmptyState.swift`
  Empty, no-results, and board placeholder states.
- `UI/SwipeFile/SwipeFilePlaceholderDiscoverView.swift`
  Polished Discover placeholder.
- `Canvas/UnifiedSidebar/SidebarSwipeFileSection.swift`
  Sidebar subrows for all swipes and board placeholders.

Modify:

- `Canvas/UnifiedSidebar/UnifiedSidebar.swift`
  Add `SidebarDestination.swipeFile` and `SidebarDestination.discover`; add `SidebarContext.discover` / `swipeFile` if the current context-tab model remains.
- `Canvas/UnifiedSidebar/SidebarNavSection.swift`
  Add top-level `Home`, `Discover`, and `Swipe File` rows if this file remains the right top-level nav location.
- `Navigation/MainView.swift`
  Render `SwipeFileHomeView` and `SwipeFilePlaceholderDiscoverView` as non-canvas destinations.
- `UI/CommandK/SwipeGalleryCardView.swift`
  Keep it canonical; make only narrow additions needed for full-library reuse, such as a dedicated reusable card variant or interaction callbacks.
- `UI/CommandK/CommandKViewModel.swift`
  Optionally delegate swipe loading/filtering to `SwipeLibraryViewModel` or shared filtering helpers after tests exist.
- `CosmoOS.xcodeproj/project.pbxproj` / `project.yml`
  Include new Swift files if the project generator does not auto-include them.

## Interaction Contracts

### Open Swipe Study

Opening a swipe from the full library should use the same focus-mode notification contract as Command K:

```swift
NotificationCenter.default.post(
    name: .enterFocusMode,
    object: nil,
    userInfo: ["type": EntityType.research, "id": item.entityId, "commandKTab": "swipeGallery"]
)
```

The final implementation can rename the metadata key later, but it should preserve existing focus-mode behavior.

### Search Row

`Search` in the sidebar should open Command K. It should not navigate to the Swipe File search field, because the user explicitly distinguished Command K as the finder.

### Discover

Discover should route to a real placeholder destination, not silently do nothing. The placeholder should establish the future product direction:

- high-performing posts
- platform filters
- time window / performance multiple controls
- not implemented yet

It should not scrape, import, or analyze external content in this pass.

### Boards

Boards are sidebar UI only:

- `+ New Board` can show a disabled/future state or lightweight non-persistent placeholder.
- Preset rows can visually select but should not filter unless the implementation maps them to existing smart presets.
- No saved data model yet.

## Empty, Loading, and Error States

### Empty Library

Show a calm centered state:

- icon: `bolt.fill` or `rectangle.stack.badge.plus`
- title: `No swipes yet`
- subtitle: `Capture posts, videos, and threads to build your creative reference library.`
- CTA: `Open Command K` or `Capture Swipe` if capture can be safely reused

### No Results

Show filter-aware empty state:

- title: `No matching swipes`
- subtitle mentions active search/filter
- CTA: `Clear Filters`

### Loading

Use skeleton shelf/card placeholders with stable dimensions. Avoid spinners in the main content area.

### Thumbnail Failure

Use platform-colored typographic covers with:

- platform icon
- first meaningful words of hook/title
- subtle border
- no blank gray cards

### Discover Placeholder

Show a polished but honest placeholder. It should feel intentionally designed, not unfinished:

- title: `Discover`
- subtitle: `High-performing posts will appear here once discovery is connected.`
- do not render inactive fake controls unless they are clearly disabled and useful for setting future direction

### Board Placeholder

If a board row is selected, show:

- title: board name
- subtitle: `Boards are sidebar-only in this pass.`
- no primary action until board creation is implemented
- link back to `All Swipes`

## Accessibility

Required:

- All icon-only controls have `.accessibilityLabel`.
- Card groups combine thumbnail, title, platform, creator, and hook metadata.
- Filter chips expose selected/not selected state.
- Search field has a clear label.
- Cards are keyboard reachable if the grid implementation supports it safely.
- Minimum interactive target size is 44pt where practical.
- Reduced Motion and Reduced Transparency are respected.
- Text should not overlap inside card captions at minimum supported widths.

## Performance

The library should remain smooth with hundreds or low thousands of swipes.

Requirements:

- Use lazy stacks/grids.
- Avoid heavy per-card computation in `body`.
- Precompute searchable text and facet counts.
- Filter on a detached task with generation cancellation.
- Thumbnail extraction should remain async and cached.
- Shelves should derive from already loaded `SwipeGalleryItem` values, not refetch.
- Avoid observing a massive `CommandKViewModel` object from the full destination.

## Testing Strategy

Unit tests:

- `SwipeLibraryFilteringTests`
  - search matches title, hook, creator, niche
  - platform filter narrows correctly
  - hook/framework multi-select works
  - fear-hooks smart preset matches expected hook types and keywords
  - search and filters combine conjunctively
  - sort modes are stable
  - shelf derivation returns deterministic rows

- `SidebarNavigationTests` or existing sidebar tests
  - new destinations are equatable/hashable
  - selecting Swipe File routes to the new destination
  - Search row opens Command K rather than a blank screen

- Existing Command K tests
  - remain passing after extracting shared swipe filtering logic

Build verification:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Manual visual QA:

- Sidebar expanded and collapsed
- Swipe File empty, loading, no-results, populated
- Grid and clustered modes
- Search typing and filter changes
- Tall reels, landscape YouTube, carousel, X/thread text, clipboard/raw note
- Light/dark or available theme variants
- Reduced motion
- Reduced transparency
- Wide window, narrow window, and minimum app width

## Out of Scope For This Pass

- Real custom board persistence
- Drag/drop swipes into boards
- Board CRUD
- External Discover ingestion
- Ranking high-performing posts from platforms
- New swipe analysis taxonomy migrations
- Replacing Swipe Study focus mode
- Rebuilding Command K
- New database schema unless required by a narrow testable bug fix

## Acceptance Criteria

The implementation is successful when:

- The sidebar has Home, Discover, Swipe File, and board placeholder UI in the requested hierarchy.
- Swipe File opens as a real full-window destination, not a modal and not Command K.
- The full Swipe File view loads existing swipes from the current atom/swipe system.
- The screen has Apple-grade visual hierarchy: masthead, search, filters, shelves, and gallery.
- Thumbnails are the dominant visual element and handle all platform formats gracefully.
- The user can filter by hook/style/format/platform/creator/niche/study state and use smart presets like Fear hooks.
- Cards open existing Swipe Study behavior.
- Empty/loading/no-results states are polished.
- Filtering logic is testable outside SwiftUI.
- Command K remains the fast finder and is not weakened by this work.

## Self-Review

- Placeholder scan: no `TBD`, `TODO`, or unresolved implementation placeholders remain. Future work is explicitly listed as out of scope.
- Internal consistency: the design keeps Command K as finder/action layer and makes Swipe File a first-class browsing/study destination.
- Scope check: this is one cohesive implementation wave because Discover and Boards are UI placeholders while Swipe File is the only fully functional new surface.
- Ambiguity check: custom boards have no persistence in this pass; Discover has no external data pipeline; Fear hooks are implemented as a smart preset over existing metadata rather than a new taxonomy migration.
