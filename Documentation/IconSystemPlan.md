# CosmoOS icon system

Design direction and implementation plan · 5 September 2026

## The decision

Do not make every icon custom. Make every icon intentional.

Cosmo should feel like one carefully designed instrument: recognizable places, stable object identities, familiar tools. An original icon is worth making when it makes a Cosmo concept easier to recognize. Originality alone is not a usability improvement, and icon work alone cannot establish that an app deserves an award.

The emotional arc: **I know where my work lives → I recognize it instantly → I get back to making it.**

Eight original symbols form the signature family: Spaces, Command, Content, Swipe File, Idea, Concept, Research, and Pipeline. Native SF Symbols handle common navigation, editing, status, and system actions. Personal space marks, user-chosen emoji, thumbnails, favicons, and platform marks remain meaningful content.

## What the audit found

The initial source scan found 1,558 literal image-symbol references and 292 distinct literal names in 984 Swift source files, excluding tests, build output, scripts, and hidden folders. This is a baseline inventory, not a count of visible controls: models also return symbol names dynamically, and some source belongs to retired surfaces.

The problems were semantic before they were artistic:

| Meaning | Previous representations | Result |
|---|---|---|
| Concept | people, link, circled link, connected points | People and relationships were visually confused |
| Research | magnifying glass, book, books, page with magnifier | Search and source objects shared a mark |
| Swipe | bookmark, stack, bolt, bolt in square, research book | The same saved inspiration changed identity between surfaces |
| Content | filled document, rich document, several local variants | Object identity depended on where it appeared |
| Space | grouped rectangles and generic document fallbacks | Space objects lost their identity in some lists |
| Active destination | a separate filled-symbol table | Selection could change silhouette and visual weight |

The recent sidebar's row spacing, text hierarchy, single selection wash, and personal space identities are already useful. Preserve them. The installed app observed during the audit was an older build with a compact icon strip, so it is not a pixel-accurate baseline for the current source sidebar.

## The complete vocabulary

| Family | Meaning / visual metaphor | Treatment |
|---|---|---|
| Places | Spaces: three arranged work panels | Custom `cosmo.space` |
| Places | Command: a compass that orients the day | Custom `cosmo.command` |
| Places / objects | Content: a manuscript with a turned corner | Custom `cosmo.content` |
| Places / objects | Swipe File: saved cards with a bookmark | Custom `cosmo.swipe` |
| Objects | Idea: a simple bulb without decorative rays | Custom `cosmo.idea` |
| Objects | Concept: three connected nodes | Custom `cosmo.concept` |
| Objects | Research: a tabbed source volume | Custom `cosmo.research` |
| Views | Pipeline: three columns containing work | Custom `cosmo.pipeline` |
| Capture | Inbox, capture lanes, capture aliases | Native tray, paired trays, terminal; user lanes retain chosen marks |
| Planning | Today, upcoming, anytime, someday, logbook | Native sun, calendar with clock, stack, archive, checked stack |
| Planning | Habits, reports, calendar | Native repeat, chart, calendar |
| Exploration | Discovery | Native binoculars; stays distinct from Command’s compass |
| People | Clients, creators | Native profile card, people; never reuse these for Concepts |
| Collections | Projects, areas, boards, library | Native folder, stack, grid, books |
| Objects | Notes, tasks, images, files, extracts, templates | Native and descriptive; file subtype/thumbnail outranks generic type |
| Research workspaces | Deep Dive, inquiry, questions, lexicon | Retain existing native object marks; do not invent metaphors without recognition testing |
| Actions | Search, add, close, share, delete, undo, move, duplicate | Standard SF Symbols; preserve spatial and keyboard conventions |
| Navigation controls | Back, forward, disclosure, sidebar, inspector, split | Standard directional/layout symbols; no original artwork needed |
| Editor | Bold, italic, headings, lists, quotes, tables, links, alignment | Native typographic tools; labels/tooltips describe the operation |
| Media | Play, pause, volume, recording, microphone, camera | Native stateful symbols; red reserved for recording or danger where already meaningful |
| Status | Complete, error, warning, offline, sync, progress, lock | Native distinct shapes plus accessible text; state is never color alone |
| AI | Assistant, an actual generation action, working state | Retain the companion/assistant identity; do not stamp sparkles on ordinary actions |
| Brands | Social platforms, providers, app integrations | Retain platform identity components; no blanket recoloring of logos |
| Personal identity | Spaces, projects, lanes, boards, companion | Preserve explicitly chosen names, emoji, marks, and colors |
| Empty states | No content, no matches, disconnected, denied | One relevant mark at most; explanatory text and next action do the teaching |

This table covers the app's icon families, including uncommon states. It does not claim that every literal symbol must migrate to an enum case. A one-off native `xmark` is already clear; wrapping it adds no value.

## Drawing specification

- Original vector paths on a 24-unit working grid. Rounded stroke ends and joins; a shared curve language; open counters.
- Nine actual stroke weights and three symbol scales, expanded to filled paths for the native asset compiler. Regular master stroke: 1.65 units. These are practical production masters, not a substitute for optical review at each size.
- Artwork is authored in `scripts/generate_cosmo_symbols.swift`; generated `.symbolset` SVG files live in `Resources/Assets.xcassets/CosmoSymbols`. Do not hand-edit generated assets.
- Native symbol rendering lets text size, weight, scale, and foreground styling flow through SwiftUI. No raster icons, network assets, per-frame path generation, or fixed bitmap scaling.
- Use the existing sidebar's 20-point glyph column and text scale. Keep labels aligned even though glyph silhouettes have different natural widths.
- Readability is judged at real 12–20 point interface sizes first, enlarged artwork second. Custom and native marks must have comparable apparent size and darkness.
- Directional actions retain system mirroring behavior. Original object drawings contain no direction-dependent navigation semantics.

## State, color, motion, and accessibility

Resting chrome uses `DS.textSecondary`; active navigation uses the existing `DS.accent` and label weight. Object tints may use the existing `DS.entity*` vocabulary, especially when a type is useful metadata. User-selected colors remain user data. No new global color, typography, or radius tokens are needed.

Keep the same silhouette during selection. The selected row, tint, text weight, and selected accessibility trait already communicate state. Do not add a second badge or background around the glyph. Completion and recording are actual state changes and retain their familiar native state symbols.

No icon has idle animation. Existing hover and selection springs remain. Completion delight is a separate interaction-design task, not a requirement for this system. Reduce Motion must never affect comprehension.

An icon beside a label is decorative to VoiceOver; the row speaks its title once. An icon-only control needs an action label and tooltip. Preserve existing keyboard paths. Do not globally increase every desktop source-list row to a touch-sized row: desktop density and phone hit targets are different concerns. Check contrast on the rendered theme, not just the source color.

## Architecture and migration

1. **One vocabulary.** `CosmoIcon` owns original identities and deliberate native choices. `Image(cosmo:)` renders it without changing font metrics. `EntityType`, `AtomType`, and `Atom` expose typed identities.
2. **No string guessing.** `link` can mean an action; a Concept is an object. Do not globally replace raw strings or infer semantic types from display titles.
3. **Preserve transport contracts.** Existing APIs that explicitly require an SF Symbol name keep a native representation through `systemName`. Persisted enum raw values, user icon strings, database records, and sync contracts do not change.
4. **Fix shared surfaces first.** Sidebar place and context rows; content view switchers; library identity chips; Command-K identities; object search results; mentions; linked objects; canvas drag/selection marks; focus references. The same object must retain its identity as it moves through these surfaces.
5. **Keep honest previews.** Thumbnail → favicon or personal identity → object glyph remains the preference. An icon must never replace useful content merely to advertise the icon system.
6. **Use existing components.** The segmented switcher and identity chip accept typed icons. Do not create another icon-button, tile, badge, or toolbar framework.
7. **Phone parity.** The iOS app now carries byte-identical original symbol assets and `CosmoIcon` vocabulary. App-side adapters in `EntityStyle.swift` connect its CoreKit types to that vocabulary. The native tab bar, Studio switcher, creation fan, inbox routing and filing actions, space destinations, document and concept references, linked ideas/content, and relevant empty states use the shared identities. Existing phone routes, content thumbnails, personal marks, and editor controls remain. The touched switcher and inbox type controls have 44-point minimum targets.

## Interrogation: delete before adding

| Challenge | Decision |
|---|---|
| Is “everything custom” necessary? | No. Delete that requirement. Familiar actions benefit from familiarity. |
| Does every destination need active and inactive artwork? | No. Delete the separate active-icon table. |
| Does each page need its own type-to-icon switch? | No. Remove duplicated switches and use shared identities. |
| Would more color, borders, glass, shadows, or glow improve recognition? | No evidence. Add none. |
| Should each icon have an animation? | No. No new animation subsystem. |
| Should an icon replace a visible label? | No. Keep labels for destinations and ambiguous actions. |
| Should the app invent a symbol for every internal atom subtype? | No. Technical subtypes do not need a new user vocabulary. |
| Can we replace all sparkles/bolts mechanically? | No. Some are real status/action symbols. Review the meaning at the call site. |
| Should private user choices be restyled for uniformity? | No. Their individuality is meaningful. |
| Should navigation destinations move during this pass? | No. Fix recognition first; changing location and metaphor together adds relearning. |
| Does “award-winning” provide a measurable acceptance test? | No. Recognition, consistency, legibility, accessibility, and responsiveness do. |

## Validation and rollout gates

**Engineering:** compile the asset catalog and full macOS app; inspect compiler diagnostics; check that each asset is present and nonempty; preserve existing user work; confirm no persistence migrations or dependencies were added.

**Visual:** render original symbols alongside native neighbors at caption, row, and large sizes; inspect regular/medium/semibold, light/dark backgrounds, monochrome selection, and native baseline alignment. Look specifically for overloaded Swipe/Research details and the weight of Pipeline's narrow columns.

**Workflow:** trace a content creator's capture → find swipe → create idea → draft → schedule path and a knowledge worker's source → concept → note → project/task path. Identity should survive every transition. Check sidebar, Command-K, library lists, mentions, focus references, and drag previews.

**Human recognition:** before calling the set final brand artwork, test it with representative knowledge workers and creators. Ask what each symbol means at interface size, both without and with its label. Compare against the previous icon, record confusions and time to locate a destination, and keep the clearer option. A practical release goal is no regression in labeled task completion; unlabeled recognition is diagnostic, not a reason to remove labels. No recognition study has been performed in this coding session.

**Deferred deliberately:** custom status symbols, custom editor controls, animated icon states, icon personalization settings, a new icon browser in the app, automatic icon inference, and a cross-platform asset service. None is necessary to deliver this improvement.

## Design references

Apple's [SF Symbols guidance](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) and [custom symbol workflow](https://developer.apple.com/documentation/uikit/creating-custom-symbol-images-for-your-app) provide the native integration model. [SF Symbols](https://developer.apple.com/sf-symbols/) supports consistency with system typography. [Things](https://culturedcode.com/things/) is a useful product reference for calm, legible task navigation. These are references, not a claim that copying their icons would give Cosmo their quality.

## Delivered in this change

- Eight original native symbol assets; 216 weight/scale drawings, compiled by Apple's asset tool.
- A shared `CosmoIcon` vocabulary and model adapters; native symbol-name boundary adapters remain where required.
- Migration of the sidebar, planning rows, content switchers, Command-K identity chips and prefixes, library lists/grids, object mentions/references, canvas selection marks, navigation history, and drag previews.
- Removed the active/inactive sidebar symbol table, the unused Command-K tab symbol table, the local Command-K, research, synthesis, and assistant type helpers, the library's duplicate kind-symbol switch, and its old hardcoded type-icon assignments.
- Preserved existing navigation behavior, personal marks, previews, labels, and system controls.
- Native light and dark optical specimens in `Documentation/Design/`. These show real compiled symbols, not raster mockup substitutes, and are explicitly labeled as offline specimens.
- Visual corrections after inspection: larger optical scale beside SF Symbols; a Spaces silhouette distinct from the sidebar toggle; separate metaphors for Command and Discovery.
- iOS parity: the same eight symbol sets and vocabulary in `CosmoOS-iOS`, with typed model adapters and 29 app source files updated. Deleted its duplicated creation/type icon maps and the inbox's separate type-label, icon, and tint switches. The iPhone's broader Library destination keeps the library meaning; its individual Spaces use the Space mark. The concurrently introduced composer components also accept the shared identities. This does not add Mac-only destinations to the phone.

To regenerate artwork:

```sh
swift -module-cache-path /tmp/cosmo-icon-module-cache scripts/generate_cosmo_symbols.swift
```

After changing the family, copy `Core/CosmoIcon.swift` to the iOS app's `CosmoiOS/Sources/Design/CosmoIcon.swift` and the generated `CosmoSymbols` folder to its asset catalog. Verify byte equality before building both apps. Keep a single drawing source; do not refine the iOS copy independently.

To regenerate the optical specimens after building the app:

```sh
swiftc -parse-as-library -module-cache-path /tmp/cosmo-icon-module-cache Core/CosmoIcon.swift scripts/render_cosmo_icon_proof.swift -o /tmp/render-cosmo-icon-proof
/tmp/render-cosmo-icon-proof /path/to/built/CosmoOS.app Documentation/Design
```

The specimen renderer checks that every original symbol can be loaded through AppKit’s native symbol API and that all 28 curated native/fallback names resolve. Interface-size, regular, semibold, and selected examples render in both appearances. Final recognition testing and a complete interactive app walkthrough remain distinct from these checks.

### Verification record

- Asset compilation: passed. Existing app-icon size warnings are unrelated to the new symbol sets.
- Asset structure: eight sets, each with 27 distinct nonempty masters.
- Runtime asset checks: eight original symbols and all 28 curated native/fallback names load successfully.
- Optical review: native SwiftUI renders at 12, 16, 20, and 32 points; regular, semibold, selected; light and dark backgrounds. Adjusted optical scale and the Spaces silhouette after the first render.
- Swift syntax and patch whitespace: passed.
- iOS source checks: all 29 affected Swift files parse and patch whitespace passes. The vocabulary and all eight symbol asset sets match macOS byte for byte.
- Full macOS and iOS Debug builds: attempted with `xcodebuild`, but not verified to completion. Extended verification was stopped during compilation. Earlier attempts encountered disk exhaustion and concurrent changes; the task's isolated simulator has been shut down. No iPhone runtime screenshots or complete interactive walkthrough are claimed.
- Incidental compile corrections: changed the editor's invalid `.image` case to `.imageRef`, explicitly annotated a chat archive filtering closure's optional return type, and replaced two nonexistent `DS.radiusPanel` references in the concurrent focus-panel change with `DS.radiusLarge`. The new iOS composer file was registered by the concurrent work, and its Idea/Swipe rows were adapted to the shared icon vocabulary.
- No claim of a completed human recognition study or complete interactive app walkthrough.
