# Collapsible Document Headings Design

Date: 2026-05-22
Status: Approved direction, pending written-spec review
Scope: Shared rich-document headings in Note Focus Mode and Content Focus Mode

## Goal

Make Heading 1, Heading 2, and Heading 3 blocks collapsible everywhere the shared focus editor is used, starting with Note Focus Mode and Content Focus Mode. A heading collapses the document content that belongs to that heading section, and the heading navigator lets the user move through sections quickly without covering the current writing UI.

## Product Behavior

### Collapsible Headings

Every `RichBlockKind.heading1`, `heading2`, and `heading3` block becomes a section header with a persisted collapsed state.

The section owned by a heading includes every following block until the next heading of the same or higher level:

```text
Heading 1: Launch Notes
  paragraph
  Heading 2: Draft
    paragraph
    Heading 3: Hook
      paragraph
  Heading 2: Polish
    paragraph
Heading 1: Archive
  paragraph
```

Collapsing `Launch Notes` hides the paragraphs and nested H2/H3 sections below it until `Archive`. Collapsing `Draft` hides its paragraph, `Hook`, and Hook's paragraph, but leaves `Polish` visible.

Collapse state is per heading block instance and persists with the document. Changing the heading text does not reset its collapse state.

Collapsed content remains stored and remains included in `RichDocument.plainText`, search/export, and AI context. Collapse only changes the editor and navigation presentation. This matches existing collapsed Element behavior and prevents hidden text from disappearing from context-aware features.

### Heading Creation

Users create headings through the existing `/` menu commands:

- Heading 1
- Heading 2
- Heading 3

Users can also keep existing keyboard/menu formatting paths. The shared command behavior should stay in `CosmoDocumentEditor` / `TextKitCoordinator`, so Note Focus Mode and Content Focus Mode do not each implement separate heading logic.

### Enter Outside A Collapsed Section

When the cursor is on a collapsed heading and the user presses Return, the editor inserts a normal paragraph after that collapsed heading section, outside the hidden content.

For example, with this document:

```text
Heading 1: Launch Notes [collapsed]
  hidden paragraph
Heading 1: Archive
```

Pressing Return from the collapsed `Launch Notes` heading creates:

```text
Heading 1: Launch Notes [collapsed]
  hidden paragraph
new paragraph
Heading 1: Archive
```

The new paragraph is visually shown underneath the collapsed heading and is not nested inside its hidden section.

When a heading is expanded, Return keeps the current editor behavior: it creates a normal paragraph after the heading line and resets heading typing attributes.

### Visual Treatment

Heading rows keep their current typography scale and spacing. Collapsibility adds a small chevron affordance aligned before the heading text:

- expanded: down chevron
- collapsed: right chevron

The chevron should be visible on hover/focus and remain discoverable when a heading is collapsed. It should not turn headings into card-like containers.

Collapsed headings show only the heading line. Hidden child content should not leave large blank space.

### Note Focus Heading Navigator

Note Focus Mode already has a left `ON THIS NOTE` rail. That rail should become the primary heading navigator:

- show Heading 1, Heading 2, and Heading 3 entries
- indent by heading level
- show a chevron for each heading's collapsed state
- click a heading title to scroll the editor to that heading
- click a chevron to collapse or expand the section
- highlight the active heading when the editor selection or scroll position is inside that section

This avoids a bottom overlay in Note Focus Mode and preserves the existing three-rail layout.

When there are no headings, keep a short empty state that points users toward `/ Heading 1`, `/ Heading 2`, or `/ Heading 3`.

### Content Focus Heading Navigator

Content Focus Mode already uses bottom-left overlays for word/character count and uses the lower manuscript area for AI and CTA surfaces. A persistent bottom heading strip would compete with those controls.

Content Focus should use the same shared heading navigator data but place it in the existing left marginalia area when draft headings exist:

- show a `SECTIONS` marginalia group above or near the current outline group
- use compact rows that match the existing marginalia style
- support click-to-scroll and chevron collapse/expand
- hide the group when there are no draft headings

In compact layouts, pane context, or zen mode where marginalia rails are hidden, expose headings through a small bottom-left popover button near the word counter. The button should only appear when the draft has headings and should not cover selected-text action popovers.

## Architecture

### Shared Document Model

Extend the shared rich document model with heading metadata instead of creating per-mode state:

- add a small `RichHeadingMetadata` value, or equivalent fields, to `RichBlock`
- store per-heading collapsed state
- preserve existing `RichBlock.id` so heading navigator entries can reference a stable block

The first version only needs persisted collapse state. It does not need custom heading IDs beyond the existing block ID.

### Section Tree Builder

Create a shared heading section utility in the editor domain, for example `Editor/RichDocumentHeadings.swift`.

Responsibilities:

- extract a flat heading outline from `[RichBlock]`
- compute each heading's owned block range using heading levels
- build parent/child relationships for H1/H2/H3
- answer whether a block should be visible based on collapsed ancestor headings
- find the insertion index after a collapsed heading section
- toggle collapse for a heading block ID

The utility should be pure Swift and unit tested without AppKit.

### Serialization

`RichDocumentSerializer.attributedString(from:)` should render visible blocks only when editing. When it omits content hidden by a collapsed heading, it must attach a deterministic JSON snapshot of the hidden section blocks to the collapsed heading line, using a new heading-specific attributed-string key such as `RichDocumentAttributeKeys.headingCollapsedChildrenJSON`.

`RichDocumentSerializer.document(from:)` must restore hidden section blocks by decoding that snapshot and splicing the blocks immediately after the collapsed heading block. This follows the existing Element pattern: collapsed content is not visible in the attributed text, but the attributed heading line carries enough structured information to restore the hidden blocks.

The serializer must emit the same `RichDocument.plainText` before and after a collapsed-heading round trip. Toggling collapse and saving must never delete hidden content.

### TextKit Interaction

`TextKitCoordinator` should own the shared editing behavior:

- draw or expose heading chevrons in the text view
- hit-test heading chevrons and toggle the corresponding `RichBlock.id`
- handle Return on a collapsed heading by inserting after that heading's computed section range
- keep existing slash menu and selection formatting behavior

This keeps Note Focus Mode and Content Focus Mode as consumers of shared editor behavior.

### Focus Mode Integration

`CosmoDocumentEditor` should expose optional callbacks and inputs for heading navigation:

- current heading outline
- heading collapse toggle
- request to scroll to heading
- active heading change when the editor selection changes

Note Focus Mode and Content Focus Mode should use these hooks to render navigation, but not parse headings from plain text themselves.

The existing Note Focus `refreshHeadings()` plain-text parser should be replaced with shared heading outline extraction from `bodyDocument`.

Content Focus should derive draft headings from `draftDocument`, not from the separate planning outline stored in `viewModel.state.outline`.

## Data Flow

1. User creates a heading with `/ Heading 1`, `/ Heading 2`, `/ Heading 3`, selection formatting, or an existing shortcut.
2. `TextKitCoordinator` applies heading attributes as it does today.
3. `RichDocumentSerializer.document(from:)` emits a heading block with stable ID and collapse metadata.
4. `RichDocumentHeadingOutline` extracts navigator entries from the current `RichDocument`.
5. Note Focus or Content Focus renders those entries in its rail or popover.
6. User clicks a heading chevron in the editor or navigator.
7. A shared mutation toggles that heading block's collapsed state.
8. The editor re-renders with hidden descendant blocks omitted from view.
9. Autosave persists the updated rich document without removing hidden content.

## Error Handling

If a document contains duplicate or missing block IDs from old data, assign generated IDs during decoding as `RichBlock` already does today.

If heading metadata is missing, default to expanded.

If a persisted collapsed heading owns no following content, render it as a normal heading with the chevron disabled or hidden.

If scroll-to-heading cannot find a visible target because the heading is inside a collapsed ancestor, expand the ancestor chain before scrolling.

## Testing

Add focused unit tests for:

- extracting H1/H2/H3 outline entries from a flat rich document
- computing nested section ranges by heading level
- hiding content under collapsed headings while preserving `plainText`
- toggling collapse by block ID
- inserting after a collapsed heading section
- replacing the Note Focus plain-text heading parser with shared document outline extraction
- Content Focus marginalia policy for showing heading sections only when draft headings exist

Add AppKit/editor-level tests where practical for:

- serializer round-trip preserves hidden collapsed heading content
- Return on a collapsed heading inserts outside the collapsed section

Run focused tests first, then build/test the app target:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentHeadingTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug test
```

## Acceptance Criteria

- Heading 1, Heading 2, and Heading 3 blocks can be collapsed and expanded.
- Collapsing a heading hides all content until the next same-or-higher-level heading.
- Nested heading collapse behaves correctly across H1/H2/H3.
- Collapse state persists after save, close, and reopen.
- Collapsed content remains included in plain text, search/export, and AI context.
- Pressing Return on a collapsed heading inserts a paragraph outside that collapsed section.
- Note Focus Mode shows document headings in the existing left rail and supports quick navigation.
- Content Focus Mode exposes draft headings without overlapping bottom overlays.
- The shared slash menu heading commands continue to work in both focus modes.
- Existing documents without heading metadata load expanded and save normally.
