# Notes and the floating item window

The note's job is to turn collected material into a usable thought or draft. For a knowledge worker that means sources, decisions, meeting notes, and reusable explanations. For a creator it means evidence, angle, hook, outline, script, and handoff. A note should remain useful as plain writing, with richer blocks introduced only when they help that work.

## Keep

- The existing page and block grammar, document-specific typography, width, spacing, paper, covers, and focus settings. Adding another customization surface would make these harder to find.
- Reusable Elements with nested text, links, checklists, tables, and other native blocks. This is already the appropriate extension mechanism for a brief, research log, or repeated writing structure. An executable plugin platform has no demonstrated need here.
- `@` item references. They preserve a relationship to the source instead of producing another independent copy of its text. A source reference and an editable snapshot have different meanings; a future live preview should label that distinction explicitly.
- Separate native interaction models: keyboard and whole-block selection on Mac, continuous selectable text runs and a keyboard insert menu on iPhone.

## Delete or simplify

- Removed the second SwiftUI keyboard/focus route for Mac block selection. Selection actions now use the same command mapping at the AppKit boundary, with window ownership.
- Stopped querying recents before restoring the last item. Recents are only needed when there is no open item.
- Removed whole-window offscreen compositing. No effect in that container requires flattening the entire note to a texture.
- Retained the single open note when hiding its panel, instead of discarding its editor and undo/scroll state every time. This reuses the existing view; it is not a second document cache. Other item types retain their teardown behavior.
- The retention tradeoff is one mounted note's memory while hidden. It improves the reopen path; it does not remove the first mount cost. No larger cache, speculative preloading, or new performance preference was added.
- Kept sharing to an explicit full-note copy. A shared preview, an internal item link, and multi-user collaboration must not be presented as equivalent.

## Correctness changes

- Selection gestures activate the keyboard route consistently; events in another window cannot mutate the selected note.
- The main Command Center keyboard monitor previously consumed Delete and arrow keys from the floating note once its text cursor resigned. Page-level monitors now defer to floating panels and document selections. Command-K searches within the item window.
- Copy and Cut are visible in the block menu. Command-C remains standard; Option-C is a selection-only alias that takes precedence over Capture Anywhere inside the owning window.
- Delete handles a whole selection; deleting everything retains an editable blank paragraph. Cut deletes only after successful clipboard writing.
- Structured clipboard payloads also work for blocks with no text. Markdown includes nested Elements, toggles, folded sections, inline marks, and links. Images with a shared HTTPS URL retain it; local-only images and sketches have a textual placeholder. Markdown is a portable text export, not a complete media archive.
- Duplicates and reusable template insertions regenerate nested, folded, and table identities.
- Hiding flushes the active text buffer before saving. Hidden notes release editing locks and assistant presence; clean hidden notes accept observed body updates.
- iPhone Share reads the full live note, not the saved card preview. Reading taps on references open the linked item; references inside nested Elements/sections receive navigation callbacks too.
- iPhone preserves Element colors and starter blocks in the same fields as Mac. Its insert menu can insert enabled definitions from the existing synced `cosmo.note_elements` preference.

## Collaboration and sharing

The implemented handoff is a full-note copy through the system share sheet, plus Copy Markdown on Mac. It does not send anything automatically. The existing sync is useful for the same person's devices; it does not establish permission for another person to read or edit a note.

Actual coauthoring needs a separate, concrete design: invited membership; reader/commenter/editor roles; revocation; attachments covered by the same access rules; attribution; conflict behavior; version recovery; and offline reconnection. Adding a public URL button before those contracts exist would be misleading. No public sharing, invitations, or collaborative editing backend was added in this pass.

## Remaining limits worth addressing when demonstrated

- Live previews of linked items are different from the existing references and Elements. A useful first version would be a compact, optionally expanded source preview, with an explicit "Open source" action, cycle prevention, and a clear stale/offline state. Rendering an entire workspace inside another note is unnecessary.
- Mac multi-block selection and iPhone text selection are not full feature parity. Cross-container batch object selection on touch needs a native explicit Select mode; forcing desktop block gestures into touch text editing would make selection less predictable.
- iPhone inserts and edits synced Elements but definition authoring remains on Mac. A separate mobile template studio is not needed to fix insertion.
- Markdown sharing cannot carry local image bytes, sketches, paper styling, or private source access. A packaged document export is a separate future capability.
- Note refresh and simultaneous edits across devices still depend on existing repository and sync conflict handling. This pass does not claim real-time collaborative merges.

## Verification

Regression coverage was added for Option-C mapping, complete folded/nested copy, fresh duplicate identities, a real mounted editor's copy/delete/undo flow, another-window rejection, and iOS Element compatibility.

- Current changed Mac and iOS sources, including the added tests, pass Swift syntax parsing. Both repositories pass `git diff --check`.
- The full Mac and iOS Xcode build attempts failed when the shared disk filled. The Mac regression build was retried after recovering space, then stopped when competing builds stalled progress and disk space fell again. No Mac test pass or performance result is claimed. Temporary output from this task's failed builds was removed; source changes were preserved.
- The iOS `CosmoCoreKit` target built and all three `NoteElementParityTests` passed on the iPhone simulator: color preservation, fresh nested template identities, and legacy definition compatibility. The completed run is recorded in `/tmp/cosmo-notes-ios-core-tests.log`. This validates the models, not the full iPhone UI.
- The installed Mac app was repeatedly replaced/relaunched during inspection and still showed the old shortcut and toolbar when available. Final visual and keyboard checks against a current app build remain outstanding. No speed multiplier is assumed from the code changes.
- Runtime inspection created a scratch note titled **New Note**, starting **Selection verification — first paragraph**. App timeouts prevented reliable cleanup; this note contains only the synthetic test paragraphs.
