# Command-K Header Art Direction Design

Date: 2026-05-09

## Goal

Replace the current ad hoc Command-K header illustrations with content-backed mastheads that feel calm, intentional, and native to CosmoOS. The header should signal the active domain using real objects, thumbnails, ideas, and covers instead of invented decorative scenes.

## Design Principle

Each expanded Command-K tab uses the same composition contract:

- Left 32%: title, item count, and tab controls only.
- Right 68%: real domain preview content, aligned to a shared optical baseline.
- No dead action buttons in the header.
- No art below the header baseline.
- No procedural scatter of unrelated shapes.
- Per-tab personality comes from actual domain content, not from random decoration.

## Composition

```text
┌────────────────────────────────────────────────────────────────┐
│ Title zone, fixed width      Content preview zone              │
│                                                                │
│ Database                     recent object rows                 │
│ 491 items                    centered on optical baseline       │
│                                                                │
│ [All Objects] [Recent]      live content, restrained detail     │
└────────────────────────────────────────────────────────────────┘
```

## Header Scenes

### Database

Signal: a live object index.

The masthead should show recent object rows with type, timestamp, and short labels. It should not use floating papers or an abstract connection graph.

### Swipe File

Signal: a media contact sheet.

The masthead should show real swipe thumbnails when available, with compact titles underneath. Placeholder cards are allowed only while data is loading.

### Ideas

Signal: grouped idea snippets.

The masthead should show a small grid of real idea titles and client/status labels. It should feel like the top of the ledger below, not a separate illustration.

### Library

Signal: library covers.

The masthead should show real Readwise covers when available. Fallbacks should use subdued source glyphs rather than invented shelf art.

## Implementation Shape

Introduce a shared `CommandKHeaderPreviewComposer` and content-backed masthead renderer. They own:

- the right-side preview-zone bounds,
- the data-to-preview projection for each tab,
- image-backed thumbnails/covers,
- skeleton fallbacks while content is loading,
- shared material opacity and shadow rules.

Each domain-specific preview should describe only real content. It should not decide global position or header layout.

## Acceptance Criteria

- Database item count is never overlapped by chips or preview content.
- Swipe File uses real thumbnails when loaded.
- Database uses object rows, not an abstract graph.
- Ideas and Library are content-backed, not game-like floating-icon scenes.
- Every tab uses the same masthead composition contract.
- The implementation builds and the Command-K focused tests pass.
