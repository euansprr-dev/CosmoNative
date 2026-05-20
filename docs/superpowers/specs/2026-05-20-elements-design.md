# Elements Design

Date: 2026-05-20
Status: Approved direction, pending written-spec review
Scope: Shared note/content rich-document Elements, slash menu insertion, and Sanctuary settings management

## Goal

Add reusable "Elements" to CosmoOS writing surfaces. An Element is a named, icon-bearing, rounded document container that can be inserted through the `/` menu, edited inline, nested inside other Elements, collapsed per inserted instance, and managed from Sanctuary settings.

Elements should work anywhere the shared rich document editor is used, especially note focus mode, content focus mode draft writing, and note blocks on the canvas.

## Product Behavior

### Element Definitions

An Element definition is global user configuration:

- stable ID
- title
- SF Symbol icon name
- creation and update timestamps
- disabled/deleted state

Definitions power search and insertion in the slash menu. They are not the document content itself.

The implementation should avoid the name `CodexElement` because that type already represents Content Physics codex records.

### Element Instances

An inserted Element instance lives inside a `RichDocument` block. It stores:

- the referenced definition ID
- title snapshot
- icon snapshot
- per-instance collapsed state
- nested child blocks

Collapse is per inserted instance. Two instances of the same global Element can have different collapsed states in the same or different documents.

Snapshots make existing documents readable even if a global definition is later renamed, disabled, or deleted.

### Visual Treatment

Expanded Elements render as compact rounded-corner containers:

- header row with chevron, icon, and editable title label
- subtle border and surface fill using existing `DS` semantic colors
- nested content area below the header
- nested Elements inset slightly so hierarchy is visible without becoming bulky

Collapsed Elements render as a compact rounded header only. Child content remains persisted and included in plain text, search/export, and AI context; collapse only changes visual presentation. Collapsing an Element must not change the document's `plainText` output.

### Slash Menu

The existing `/` menu should become data-driven enough to combine static editor commands with user Element definitions.

Expected behavior:

- `/` opens the existing menu.
- Typing an existing Element title filters it into the menu.
- Selecting an existing Element inserts an instance at the current cursor.
- `/new element` or a "New Element" row opens a small create popover.
- The create popover captures title and SF Symbol icon, saves the definition, and inserts the new Element immediately.

The menu should keep current keyboard behavior: arrow navigation, return to select, escape to dismiss, and outside-click dismissal.

### Settings

Sanctuary settings gets a new `Elements` tab.

The tab manages global definitions:

- list existing Elements with icon and title
- create a new Element
- rename an Element
- change its icon
- disable/delete an Element so it no longer appears in `/` search

Deleting or disabling a definition must not remove or corrupt existing inserted instances.

## Architecture

### Shared Model

Create focused model types under the editor domain:

- `DocumentElementDefinition`
- `DocumentElementStore`
- `RichElementReference` or equivalent metadata embedded in `RichBlock`

`DocumentElementStore` should persist definitions as JSON under Application Support, following the lightweight local-file pattern already used by `CommandKUserCommandStore`. This avoids a database migration for a user-customization feature and keeps the first version scoped.

### Rich Document Model

Extend the shared rich document model:

- add `RichBlockKind.element`
- add optional Element metadata to `RichBlock`
- add `children: [RichBlock]` or an equivalent child-block field for nested content

`RichDocument.plainText` should include Element boundaries in a readable way while preserving nested content, for example:

```text
[Audience]
Nested content
[/Audience]
```

The exact plain-text markers should be deterministic and test-covered because they affect search, AI context, and exports.

### Editing Boundary

SwiftUI remains the source of truth for document state. AppKit is used only for TextKit behavior that SwiftUI cannot express cleanly.

The smallest bridge is the existing `CosmoTextView` / `TextKitCoordinator` path:

- slash menu selection posts an insertion command with the selected Element definition
- `TextKitCoordinator` inserts an attributed Element marker/range at the cursor
- custom attributes identify Element ranges during serialization
- custom drawing or attachment-backed rendering provides rounded-container visuals while editing
- serializer converts attributed ranges back into structured `RichBlock(kind: .element, children: ...)`

If full nested editable containers prove too large for one pass, the fallback is still structured `RichDocument` storage with a conservative first editor rendering that keeps content editable and round-trippable. The implementation must not store Elements as plain decorative text only.

### Rendering Boundary

`CosmoDocumentRenderer` should render Element blocks recursively for read-only/previews. This covers canvas note blocks and any existing rich-document previews without duplicating UI.

`CosmoDocumentEditor` and `RichTextEditor` should expose no Element-specific API to consumers unless needed. Feature behavior should flow from the shared document model and slash menu.

## Data Flow

1. User opens a note/content document using `CosmoDocumentEditor`.
2. User types `/`.
3. `SlashCommandMenu` loads static commands and Element definitions from `DocumentElementStore`.
4. User selects an existing Element or creates a new one.
5. `TextKitCoordinator` inserts an Element block instance at the current selection.
6. `RichDocumentSerializer.document(from:)` serializes the editor content into structured blocks.
7. Existing save paths persist the updated `RichDocument` through existing metadata fields.
8. `RichDocumentSerializer.attributedString(from:)` restores Element styling and collapse metadata on reload.

## Error Handling

If the Element store file is missing or corrupt, the store should return an empty definition list and preserve the corrupt file by moving it aside with a timestamped suffix before writing a fresh file.

If an inserted instance references a deleted or missing definition, render the title/icon snapshot and mark it as a local/snapshot Element in settings or menus only if explicitly edited later.

If an icon name is invalid, fall back to `square.stack.3d.up` in UI while preserving the stored value until the user changes it.

## Testing

Add focused unit tests for:

- Element definition persistence and search ranking
- rich document encode/decode round-trip for nested Element blocks
- `plainText` output is identical for expanded and collapsed Elements
- serializer round-trip for Element title/icon/collapsed metadata
- slash command filtering includes static commands and matching Elements
- deleted definitions disappear from slash menu but existing document instances still render

Add a build verification step with:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug test
```

## Acceptance Criteria

- Existing documents without Elements still load and save.
- Users can create an Element from the slash menu and insert it immediately.
- Users can insert an existing Element by typing its title in the slash menu.
- Element instances render as rounded blocks with icon, title, and nested content.
- Element instances can be nested inside other Element instances.
- Collapse state is per inserted instance and persists with the document.
- Collapsed content remains available to plain text, search/export, and AI context.
- Sanctuary settings includes an Elements tab for create, rename, icon change, and disable/delete.
- Note focus mode, content focus mode draft editing, and canvas note blocks all use the shared behavior.
- Focused tests pass, and the app target builds.
