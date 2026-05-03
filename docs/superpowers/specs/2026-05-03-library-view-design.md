# Finder-Grade Canvas Library Design

Date: 2026-05-03
Status: Design approved for implementation planning
Selected direction: View B, "Cosmo Finder"

## Goal

Redesign `UI/Library` so the user's canvases feel as polished and navigable as Finder icon view while still feeling native to CosmoOS. The library should make projects, canvas clusters, thinkspaces, and loose documents feel like real objects in one coherent workspace.

The desired emotional arc is: the user arrives feeling that their canvas library is a flat list, and leaves feeling that every thought has a visible home.

## Current Context

The current library already has the main ingredients:

- `LibraryView` owns search, sorting, smart collections, breadcrumbs, project folders, and standalone items.
- `LibraryViewModel` builds `LibraryItem` values from atoms, projects, and thinkspaces.
- `LibraryGridView` renders a masonry card grid with rich preview areas.
- `CortexDatabaseBrowser` already has Finder-like small document thumbnails through `SpotlightDocCard`, `SpotlightPageContent`, `SpotlightImageContent`, `SpotlightConnectionPreview`, and `SpotlightFolderContent`.
- `ThinkspaceMetadata.clusters` stores persisted `CodableCluster` records with cluster names, block UUIDs, colors, view modes, and synthesis.

The current gap is information architecture and visual rhythm. The home surface mixes cards, rows, smart collections, and a horizontal standalone rail. View B consolidates the library into a Finder-like icon browser with CosmoOS materials and real page previews.

## Visual Layout

Home level:

```text
┌──────────────────────────────────────────────────────────────────────────┐
│  Search anything...                                      [grid] [list] +  │
├──────────────────────────────────────────────────────────────────────────┤
│  Workspace                                      Date created  filter icon │
│  26 items                                                                 │
│                                                                          │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐             │
│  │ folder art │ │ folder art │ │ page art   │ │ folder art │             │
│  │            │ │            │ │ actual txt │ │            │             │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘             │
│  Ben Calls 1w  For review 1d  Auction... 2d  Posted 1w                   │
│                                                                          │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐                            │
│  │ page art   │ │ image art  │ │ folder art │                            │
│  └────────────┘ └────────────┘ └────────────┘                            │
└──────────────────────────────────────────────────────────────────────────┘
```

Project or thinkspace folder level:

```text
Home / Ben

┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
│ cluster    │ │ cluster    │ │ page art   │ │ page art   │
│ folder     │ │ folder     │ │ actual txt │ │ image      │
└────────────┘ └────────────┘ └────────────┘ └────────────┘
Ben Calls 1    For review 3   New Content   Thumbnail swipe
```

Cluster folder level:

```text
Home / Ben / For review

┌────────────┐ ┌────────────┐ ┌────────────┐
│ page art   │ │ page art   │ │ connection │
│ actual txt │ │ actual txt │ │ mini map   │
└────────────┘ └────────────┘ └────────────┘
```

## Primary Objects

### Library Object Types

The implementation should introduce a display-level library object model that can represent:

- Project folders from project atoms.
- Thinkspace folders from existing thinkspace atoms.
- Cluster folders from `ThinkspaceMetadata.clusters`.
- Free-floating documents from standalone atoms.
- Contained documents from atoms inside a project, thinkspace, or cluster.

This can be layered over the existing `LibraryItem` model or introduced as a small wrapper type if that keeps the view code cleaner. The important contract is that each rendered tile knows:

- Stable ID.
- Title.
- Object kind: project, thinkspace, cluster, atom.
- Accent color.
- Count metadata.
- Relative date.
- Optional preview text.
- Optional thumbnail URL.
- Optional navigation target.

### Cluster Folders

Clusters become real library folders. They are derived from `ThinkspaceMetadata.clusters` on each thinkspace and should appear:

- Inside the related project folder if the thinkspace belongs to a project.
- Inside the related thinkspace folder.
- At home only if there is no project hierarchy and the cluster belongs to an unassigned thinkspace that would otherwise be hidden.

Cluster folders open into the atoms whose UUIDs appear in `CodableCluster.blockUUIDs`. If a block UUID cannot be resolved to an atom, it should be ignored rather than showing broken UI.

## Visual System

### Surface

Use the CosmoOS light Greenhouse palette as the default:

- Root background: `DS.bg`.
- Tile wells: `DS.surfaceCard` for normal state and `DS.surfaceElevated` for hover/selection elevation.
- Text: `DS.text`, `DS.textSecondary`, and `DS.textMuted`.
- Accent: semantic entity colors and folder colors, never decorative random color.

The result should feel like Finder icon view filtered through the third inspiration image: warm, quiet, useful, and slightly editorial without becoming a landing page.

### Tile Design

Folder tiles:

- Large square-ish preview well: 156 points at normal desktop width, shrinking no lower than 132 points in compact windows and expanding no higher than 180 points on wide windows.
- Centered folder glyph drawn as a reusable SwiftUI shape or composed from rounded rectangles.
- Muted semantic folder colors: project green, review rose, content blue, archive gray, prompt tan, ideas green.
- Title row below the well, with an icon-size color swatch and count/date metadata.
- 8 point radius maximum on small labels; preview wells can use 12-14 point continuous rectangles to match the existing app style.

Document tiles:

- Reuse the CMD-K thumbnail language for actual previews.
- Page previews render tiny readable texture through `SpotlightPageContent`.
- Image previews use existing thumbnail loading.
- Connection previews use `SpotlightConnectionPreview`.
- Empty documents use `SpotlightFauxPage`.
- Labels match Finder: centered under the tile, two-line title truncation, metadata secondary.

### Grid Behavior

Use an icon-grid rhythm instead of the current masonry library:

- Adaptive columns with fixed item wells, not variable-height masonry.
- Stable item dimensions so hover, selection, and title wrapping do not shift the grid.
- Folders sort before documents, matching Finder.
- Search changes the scope to all matching objects and shows provenance in the subtitle.
- Grid/list toggle remains, but grid is the default and receives the polish pass first.

### Top Chrome

The top bar should be calmer and more Finder-like:

- Large search field with "Search anything..." when at home.
- View mode segmented control using icon buttons.
- Sort label and filter icon on the right.
- Create button remains available, but it should not dominate the browsing surface.
- Breadcrumbs appear as a compact path row when inside project, thinkspace, or cluster folders.

Smart collections should not visually compete with the Finder grid. If retained, they should become filter chips below the search field or move into the sort/filter menu.

## Interaction

- Single click selects or previews a tile if selection support is added.
- Double click opens folders or opens atom focus mode, preserving existing behavior.
- Return opens the selected item if keyboard selection exists in the implementation scope.
- Context menus preserve existing actions: open, open as pane, add to canvas for atoms, delete.
- Folder entry uses a short scale/fade transition, not a mobile push animation.
- Hover subtly raises the tile well and clarifies the border; unhovered state stays quiet.

## Data Flow

1. `LibraryViewModel.loadLibrary()` fetches atoms, projects, thinkspaces, and memberships as it does today.
2. It additionally resolves thinkspace metadata for cluster folders.
3. It builds a library hierarchy:
   - home objects,
   - project contents,
   - thinkspace contents,
   - cluster contents.
4. `LibraryView` asks for the current location's objects and passes them to the grid/list renderer.
5. `CosmoFinderGridView` renders folders and documents using specialized tile subviews.
6. Navigation updates the current location and breadcrumb path; atom opening continues to use current notification routes.

## Error Handling

- Missing atom for a cluster block UUID: omit it from the folder contents.
- Empty cluster folder: show a useful empty state explaining the cluster has no visible documents.
- Missing image thumbnail: fall back to `SpotlightFauxPage`.
- Failed library load: preserve current print logging initially and show the existing empty/loading state rather than crashing.
- Deleted atoms: continue excluding them from normal browsing.

## Empty And Loading States

Loading should use skeleton icon tiles rather than a centered spinner for the main content area.

Empty home:

```text
folder icon
Your workspace is ready
Create a canvas or capture a thought to start building your library.
```

Empty cluster:

```text
folder icon
This cluster is empty
Drag documents into this cluster from the canvas to fill it.
```

Empty search:

```text
magnifying glass
No matches
Try a title, body phrase, project, or cluster name.
```

## Implementation Scope

In scope:

- Replace the home library masonry with the Finder-like icon grid.
- Introduce folder tiles for projects, thinkspaces, and clusters.
- Reuse CMD-K document thumbnails for free-floating and contained docs.
- Keep list mode functional.
- Preserve existing open/delete/context menu behavior.
- Add focused tests for hierarchy building and cluster-folder resolution.

Out of scope for this pass:

- Dragging documents between folders or clusters from the library.
- Inline renaming.
- True Finder keyboard multi-selection.
- New persistence schema for clusters.
- Rewriting the CMD-K browser.

## Testing

Add or update tests around the non-visual logic:

- Home excludes project-owned atoms but keeps standalone documents.
- Project folder shows related thinkspaces, clusters, and project atoms.
- Cluster folder resolves only visible atoms from `blockUUIDs`.
- Search includes nested/project-owned atoms and shows correct provenance.
- Sort order keeps folders before documents for each sort mode.

Run a build after implementation. If snapshot infrastructure is practical for this surface, add a preview or render snapshot for the new grid with mixed folders, documents, images, and empty states.

## Acceptance Criteria

- The library first impression resembles macOS Finder icon view in spacing, object clarity, and preview quality.
- Folders exist for meaningful canvas/project/cluster groupings.
- Standalone documents use actual page/image/connection previews rather than generic icons.
- The design feels native to CosmoOS through warm materials, muted semantic colors, and restrained chrome.
- Existing navigation and context menu behaviors still work.
- The implementation does not touch unrelated dirty files.
