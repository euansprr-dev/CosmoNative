# Atom Window Unified Toolbar Design

## Goal

Make the Atom floating window feel like one Apple/Raycast-style Liquid Glass command surface instead of a window titlebar wrapped around another focus-mode toolbar, while preserving every current Atom and focus-mode action.

## Scope

This redesign applies only when focus modes are rendered inside `AtomWindowPanelController`. Standalone focus modes, split panes, and peek overlays must keep their existing chrome unless an explicit Atom-window chrome context is present.

## Architecture

Atom owns a small environment-scoped chrome context that exposes global Atom actions: hide window, unload atom, back, forward, bookmark, open search, and create atom. `AtomWindowRootView` provides that context only inside the Atom panel. Focus-mode toolbars read the optional context and add a compact Atom command cluster when present.

The outer Atom root stops rendering a separate opened-atom titlebar. Empty/loading/generic states still get a unified Atom glass toolbar because they do not have a focus-mode toolbar to host the actions.

## UI Model

- One floating glass command row at the top of the visible surface.
- Left cluster: close, back, forward.
- Center: current atom identity or the focus-mode-native center control.
- Right cluster: bookmark, search, create, plus native focus-mode controls.
- Search opens as a Command-K-style glass overlay, with a light backdrop and warm inner surfaces.
- The panel shell uses native `cosmoGlassPanel` and a transparent host background, with content as the visual hero.

## Functional Requirements

- Atom close/hide still works from the unified toolbar.
- Atom back/forward history still works.
- Bookmark toggle still works and stays disabled with no current atom.
- Search still opens, focuses input, supports escape, arrow selection, return, recent atoms, filters, and result opening.
- Create menu still supports idea, note, content, research, and connection.
- Note toolbar keeps style, panel, graph, and close controls.
- Content toolbar keeps Writing AI, style, focus band, zen, close, and pipeline controls.
- Connection toolbar keeps navigator, view switcher, search, add source, inspector, and close behavior.
- Idea toolbar keeps status, client, Begin Writing, inspector, and close behavior.
- Research, SwipeStudy, and CosmoAI keep their native actions, with Atom controls added only in Atom context.

## Non-Goals

- No broad focus-mode redesign outside the Atom panel.
- No persistence/data model change.
- No Command-K search engine rewrite.
- No changes to non-Atom split-pane ownership rules.

## Verification

- Add source-level tests proving Atom chrome context is optional and Atom-only.
- Add source-level tests proving focus modes still gate Atom-specific controls behind environment/context checks.
- Run focused Atom/focus-mode tests.
- Run the required full app build: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build`.
