# Companion as the face of Cosmo — product and implementation plan

Prepared 5 September 2026. This is a proposed design and engineering plan, grounded in the current Mac and iPhone source. No application code is changed by this plan.

**Product decision:** make the selected companion the optional, persistent entrance to Cosmo’s assistant. A compact conversation and the existing assistant pane are two presentations of the same session. The character supplies identity and meaningful feedback; the conversation retains the assistant’s existing tools, context, review controls, and history.

The quality target is distinctive artwork, excellent everyday usability, and reliable continuity. Awards are an aspiration; the release gates below are how we judge the work.

## 1. The experience we are designing

The emotional arc is: “There is something friendly here when I need it; when I start working, my work has the room.”

Three primary presentations:

    RESTING                         COMPACT CHAT
    ┌──────────────────────────┐    ┌──────────────────────────────────┐
    │                          │    │ Workspace remains visible         │
    │        Your work         │    │        ┌────────────────────────┐ │
    │                          │    │        │ [Pip] Cosmo   Pane  ·  ×│ │
    │                          │    │        │ Using: Creative Practice│ │
    │                          │    │        │                         │ │
    │                    [Pip] │    │        │ Conversation + receipts │ │
    └──────────────────────────┘    │        │                         │ │
                                    │        │ Ask…       Context  Send │ │
                                    │        └────────────────────────┘ │
                                    └──────────────────────────────────┘

    ASSISTANT AS A PANE
    ┌───────────────────────┬──────────────────────────────────────────┐
    │                       │ Existing pane tabs                       │
    │                       │ [Pip] Assistant   Context   Compact   ·  ×│
    │      Your work        ├──────────────────────────────────────────┤
    │                       │ The exact same conversation              │
    │                       │ Same draft, stream, sources and review   │
    │                       │                                          │
    │                       │ Ask…                       Context  Send │
    └───────────────────────┴──────────────────────────────────────────┘

The drawings describe placement and hierarchy, not final artwork. The transcript is the visual priority while chat is open. The character is approximately 56–64 points at rest and a smaller portrait in chat chrome; these are prototype starting dimensions.

Core behavior:

- Clicking the resting character opens compact chat. Hover acknowledges intent and teaches “Ask Pip”; it does not open chat or start a model request.
- A clear “Open as pane” action moves that conversation into the existing pane deck.
- “Return to compact chat” moves it back. Closing either presentation preserves the conversation and unsent work.
- If the same assistant pane already exists but is behind another tab, clicking the companion reveals that pane. It does not create a duplicate chat.
- While its pane is visible, the companion lives in the pane header. When the pane is no longer visible, the corner entrance can return as “Return to chat.”
- Character mode and Minimal mode use the same assistant route. The center bubble is retired when the new entrance is enabled.
- Existing ⌥A remains a direct route to the assistant pane. We do not silently change an established shortcut into a different interaction.
- Escape closes the foremost menu, then the compact presentation; it does not erase an unsent draft, stop a run, or accept/reject edits. Clicking outside can collapse compact chat while allowing the intended workspace interaction to proceed. This deliberately replaces the old composer’s draft-clearing Escape behavior.
- The first release places the companion inside Cosmo’s active application window. A pet floating over unrelated applications would be a separate product capability.

## 2. What the source already gives us—and what it does not

| Existing foundation | Verified behavior | Consequence for this plan |
|---|---|---|
| [MainView](/Users/euanspencer/CosmoOS-Swift/Navigation/MainView.swift:306) | The bottom composer and review overlay are currently mounted together, and hidden when an inline assistant pane exists. | Separating launcher visibility from review visibility is required; replacing the composer must not strand pending edits. |
| [PaneManager](/Users/euanspencer/CosmoOS-Swift/Navigation/PaneManager.swift:515) | Stable inlineAssistant identity; existing pane is activated rather than duplicated. Maximum six panes; a full deck currently returns silently. | Reuse the identity and deck. Add an explicit success/capacity result before attempting a handoff. |
| [MainNotificationRouter](/Users/euanspencer/CosmoOS-Swift/Navigation/MainNotificationRouter.swift:330) | Pane requests from the store are immediately routed to the deck. | Introduce presentation intent so an answer in compact chat does not automatically move the interface. |
| [CosmoInlineAssistantStore](/Users/euanspencer/CosmoOS-Swift/UI/InlineAssistant/CosmoInlineAssistantStore.swift:595) | Owns the composer, running task, phases, context, proposals and transcript. Streaming text already has a narrower observable model. | Share this conversation owner across hosts. Feed character animation from a small status adapter, not every token or keystroke. |
| [Session and scope handling](/Users/euanspencer/CosmoOS-Swift/UI/InlineAssistant/CosmoInlineAssistantStore.swift:1954) | Sessions are isolated by editable surface; explicit scope pins exist; switching during a run is guarded. | A host change is not a scope change. Preserve those guards and expose the actual target in both hosts. |
| [Persisted session](/Users/euanspencer/CosmoOS-Swift/UI/InlineAssistant/CosmoInlineAssistantStore.swift:96) | Transcript, proposals, selected context, skill and ledger persist locally. Composer text and view position are not in that envelope. | Add durable draft handling and a host-transfer record; “the store is shared” alone is insufficient. |
| [Split-pane regression tests](/Users/euanspencer/CosmoOS-Swift/Tests/CosmoOSTests/SplitPaneSeatRegressionTests.swift:5) | The deck deliberately separates layout seat widths from animated clipping. Assistant transcripts also use stepped resizing. | Preserve this design during docking. Do not animate the entire transcript’s layout frame through every intermediate width. |
| [CompanionStore](/Users/euanspencer/CosmoOS-Swift/Core/CompanionStore.swift:8) | Selected identity, retained growth and independently edited rituals already exist; reactions follow successful local saves. | Retain the IDs, earned progress, and event boundaries. Add presentation and animation around them. |
| [iPhone chat](/Users/euanspencer/CosmoOS-iOS/CosmoiOS/Sources/Cosmo/CosmoChatView.swift:9) and [RootTabView](/Users/euanspencer/CosmoOS-iOS/CosmoiOS/Sources/App/RootTabView.swift:264) | A streaming chat implementation exists, but its tab is dormant. It uses agent-conversation atoms; the Mac inline assistant uses local surface-session archives. | iPhone activation is a real integration phase. Shared appearance does not establish cross-device conversation continuity. |
| [Sound settings](/Users/euanspencer/CosmoOS-Swift/Settings/SoundSettingsView.swift:5) | Shared sound profiles, volume and haptic controls already exist. | Extend this vocabulary and respect the current controls. Do not add a competing sound engine. |

The current assistant also has legacy CosmoWindow, collaborator, and specialized Inquiry/Deep Dive presentations. These are not interchangeable transcripts. The new entrance must route deliberately instead of opening another generic chat beside an existing copilot.

## 3. Artwork: a cast designed to live in the interface

**Recommended art direction: small, sculpted Greenhouse characters rendered as authored 2.5D illustration.** Think rounded botanical objects, folded paper, soft ceramic and translucent wings, with a consistent light source and restrained material detail.

The current portraits are useful identity and growth foundations. The next pass must improve proportion, pose, silhouette and expression for a living character at interface size. Simply enlarging the portraits and applying the same bounce to all twelve would fall short.

Art rules:

1. Every character must read as its own silhouette at the actual corner size.
2. Keep a common optical weight, eye language, light direction, baseline and soft contact shadow.
3. Use matte, warm materials; highlights describe form. Avoid glossy plastic, heavy outlines and decorative gradients that have no physical purpose.
4. Give each character a distinct posture and movement vocabulary. A snail should feel different from a paper plane.
5. Detail is size-aware. Tiny toolbar portraits simplify veins, spots and particles; large companion views reveal them.
6. Growth changes the character’s form, not just its color or surrounding sparkle count.
7. All four forms remain inside the same interaction bounds. Unlocking a form must not displace controls or enlarge the hit target.
8. Create authored light- and dark-surface treatments. Theme changes adjust lighting and contrast without changing the character’s recognizable identity.
9. The character itself is an object; glass belongs to surrounding controls. Avoid a permanent frosted circle enclosing every full-body pose.
10. Art does not carry critical status alone. Plain-language activity and accessible labels remain available.

### Character direction

| Companion | Character and material | Working/attention gesture | Signature reward and growth direction |
|---|---|---|---|
| Pip | Compact seed body; supple, asymmetrical leaves | One leaf inclines toward the conversation | A restrained leaf unfurl; stronger stem and a final blossom |
| Fiddle | Springy fern with a distinctive curled tip | Curl relaxes slightly as attention shifts | A frond opens in sequence; more articulated foliage |
| Delia | Broad, dignified leaf with visible structure | Small leaf tilt with a clear center of mass | A new leaf emerges; increasingly sculpted fenestrations |
| Otto | Grounded cactus in a warm clay pot | Small attentive lean; pot stays planted | A flower opens; a fuller crown with limited colors |
| Morel | Soft mushroom cap, warm underside and short body | Cap tips; body compresses very slightly | A tiny cap lift and settle; richer gills and a grown cap |
| Juniper | Calm snail carrying a small garden | Antennae orient; body remains anchored | A slow pleased nod; shell garden gains lasting details |
| Clementine | Rounded bee, softly translucent wings | Wings fold into an attentive resting pose | One contained wing flourish; richer wing and pollen details |
| Luna | Moth with elegant folded/unfolded wing silhouette | Wings settle closer while reading | One symmetrical opening; more authored wing pattern and color |
| Sol | Warm, softly dimensional sun | Rays subtly orient toward the panel | A short ray expansion; a more articulated corona |
| Sable | Crescent with a readable face and orbital detail | Small tilt; orbit stays within the silhouette | One contained orbit; a richer celestial composition |
| Wallace | Ceramic watering can with a living sprig | Body tips toward the task, without spilling | A single controlled droplet waters its own sprig; fuller planting |
| Scout | Precisely folded paper with a strong diagonal silhouette | Fold flexes toward the active conversation | A tiny in-place lift; refined folds and a short local paper trail |

These are concept briefs to validate, not twelve mandatory gimmicks. Weak gestures should be removed during art review.

### Asset production pipeline

- Begin with three representatives: Pip, Juniper and Scout. They exercise flexible growth, articulated organic form and folded geometry.
- Produce three visual treatments for those characters, then select one coherent treatment before expanding the cast.
- Create a character bible: proportions, color recipes, lighting, face placement, materials, no-go examples and all growth silhouettes.
- Build twelve layered master rigs with named attachment points and expression controls.
- Author 48 growth configurations and one unique signature response per character. Shared state animations are retargeted; do not hand-maintain hundreds of unrelated frame sequences.
- Produce contact sheets at 24/32, 56/64 and 160/240 points, on real Greenhouse and mono-theme screens.
- Preserve editable vector/layer sources and an asset manifest with version, author/provenance, bounds, baseline, expression anchors and supported states.
- Generated concept art can accelerate exploration. Production assets must be cleaned, coherent, editable, and packaged locally; no runtime dependency on an image-generation service.
- Keep the shipping renderer behind a small character-rendering interface. Start with layered native drawing/Core Animation based on the existing Canvas artwork. An alternative renderer only earns a dependency if the three-character proof demonstrates a meaningful quality advantage within the performance budget.

## 4. Animation: purposeful, interruptible and character-specific

Separate four independent inputs: **presentation**, **actual assistant activity**, **earned growth**, and **temporary feedback**. A single “happy/busy” enum cannot express a listening microphone, an awaiting-review edit, and an earned milestone accurately.

| State or event | Visual behavior | Interaction rule |
|---|---|---|
| Resting | A well-posed still character | No perpetual bounce, eye tracking, or idle animation clock |
| Hover/focus | Small attention shift and a clear tooltip/focus ring | No model call; keyboard focus receives equivalent feedback |
| Press | Immediate, modest compression and release | Respond before any network work begins |
| Open compact chat | Character identity transfers to the chat header as the panel materializes upward/inward | The transcript does not zoom across the screen; typing is available immediately |
| Planning | A recognizable thinking pose | Real status text accompanies it; no invented percentage |
| Reading/tool work | A small transition into a focused pose | Update on meaningful phase changes, not each tool event or token |
| Writing | Attentive writing pose; transcript streams normally | Long runs remain calm; Stop stays available |
| Awaiting review | Character settles and a restrained review indicator appears | Pending changes require the existing review action |
| Voice listening/speaking | State driven by the real voice pipeline | Persistent mic state and stop control remain explicit; decorative feedback cannot conceal them |
| Task/focus saved | One short personal response | Do not duplicate the task system’s sound/haptic reward |
| Milestone earned | One longer form transition at a suitable moment | Never interrupt typing, reviewing, voice or a modal workflow |
| Failure/offline | Calm, readable status and repair action | No distressed pet, guilt, repeated shaking, or pretend success |
| Closing/docking | Continuity of identity with preserved interaction state | Animations can be interrupted and reversed |

Initial tuning targets, subject to real-device review: press about 80–120 ms; attention 120–180 ms; chat opening/docking perceptually settled in about 250–350 ms; ordinary reward under 900 ms; milestone transition at most about 1.5 seconds. These are design targets, not measured performance claims.

Use the existing ProMotionSprings for interface state. Character motion needs authored anticipation, a clear center of mass and restrained follow-through. A shared spring value is not a substitute for animation direction.

**Attention policy:** explicit user input and live operational status take precedence. Ordinary rewards are coalesced; stale decorative events expire rather than playing late. Every earned milestone remains recorded even if its animation is skipped. Reduced Motion produces expressive still poses and brief opacity changes; sounds and animation never become the only status channel.

This approach follows Apple’s guidance to make motion purposeful, brief, optional and interruptible. [Apple Motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion?changes=_3)

## 5. Compact chat must be a complete assistant surface

Target a roughly 420-point-wide compact panel, with a useful minimum around 320 points and height bounded by the available window. Final dimensions are validated with long answers, large text and real tool results.

Keep:

- The same transcript renderer, streaming behavior, citations/source chips and tool receipts.
- The same context selector, quoted selection, supported context attachments, explicit skill selection and supported slash commands. Unsupported drop types get an explanation, not a silently ignored attachment.
- A normal multiline composer, send/stop controls, keyboard navigation and draft preservation.
- Reviewed edits, proposal status, undo receipts and follow-up actions.
- Clear scope wording: “Using: Creative Practice” or “General — no document.”
- A visible pane button; overflow contains companion customization, rituals, presentation preferences and appropriate conversation actions.
- Scroll-follow etiquette: follow only while the reader is at the bottom; otherwise show “Jump to latest.”
- Genuine loading, retry, missing-key, offline and unavailable-source states.

Compact chat can display ordinary answers without opening a pane. Large research results, wide comparisons and complex edit reviews can offer “Open as pane.” Do not force a pane just because the model emitted an answer or a legacy skill has a pane-oriented name.

For actions that require the source to remain visible, retain the existing in-document diff/review workflow. Review controls remain reachable even when the launcher is hidden or the companion is set to Minimal.

A local first-use label teaches the entrance. An empty chat uses two or three relevant starters based on available context, not invented knowledge of the document. No suggestions require an agent request merely because the character was hovered.

## 6. Pane integration: the non-negotiable continuity contract

A move between compact chat and a pane preserves:

- Session/conversation identity and document scope.
- The same in-flight request, cancellation handle and accumulated stream.
- Transcript message IDs, sources, activity receipts and pending proposals.
- Composer text, explicit context picks, selected skill and selection/caret position.
- Reader position by message anchor plus offset, and whether the reader was following the stream.
- Review decisions and undo state.
- The identity and growth form currently displayed.

**Move sequence:** capture presentation state → request/open or activate the existing pane → confirm that it is available → attach the same conversation owner → restore reading/composer focus → remove the old presentation. On failure, retain the old host and draft. Nothing resubmits the prompt.

The pane move itself must not call session activation, clear the composer, create a new agent, or interpret losing view focus as a change of document target.

A user dismissal also outranks subsequent automatic “ensure visible” events from that run. Streaming tokens or a completed answer may update a restrained ready indicator, but may not reopen a dismissed chat. Keep the explicit presentation intent and run ID until the user opens it again. Preserve composer undo/redo separately from document-edit Undo receipts; a host transfer must not redirect ⌘Z to the wrong undo owner.

Pane behavior:

| Situation | Required result |
|---|---|
| No panes open | Use the existing split-pane opening policy; preserve the main content’s position and selection. |
| Assistant already open | Activate its stable pane identity; do not append another. |
| Another pane focused | Open/reveal Assistant without closing other tabs. Offer “Open beside current pane” using existing split behavior when space permits. |
| A pane already pinned | Preserve that pin. No automatic unpinning to make the assistant look better. |
| Six panes already open | Compact chat stays open. Explain that the pane deck is full and let the user choose a pane to close, or keep chatting compactly. No automatic eviction. |
| Assistant tab is collapsed | The companion can act as “Return to chat” and reveal that tab. |
| Pane is closed during a run | Preserve the run; show compact activity when appropriate. Closing a view is not Stop. |
| User explicitly chooses Compact | Transfer before removing the pane. Focus the existing source pane/main view appropriately. |
| Window is too narrow | Keep a readable compact presentation, potentially using the available content width. Do not clip a forced split or discard a pin. |
| Resize or divider drag during transfer | Respect existing seat/clip architecture and stepped transcript resizing. Settle deterministically, without an extra chat host. |
| Docking is interrupted | Final state has one interactive host, one composer and one request; restore the prior valid host if needed. |

Provide a reliable toolbar action first. A drag-to-dock handle can follow once the transfer contract is proven; it must use the pane deck’s insertion/drop behavior, an explicit target preview, cancellation on Escape, and the same transactional move. Never make dragging the only way to dock.

## 7. Context, focus and multiple windows

The companion’s location is not its context. Determine context from the existing editable-surface registry and pane context owner before the click gives focus to chat.

- Opening the assistant should preserve the source selection and clearly name its owner.
- “Follow my focus” remains an explicit supported mode. Automatic retargeting is suspended while there is a draft, a running request or a pending review that would otherwise be displaced.
- A host change never changes scope.
- An intentional scope change restores that surface’s conversation and makes the change visible. Do not silently transplant selected context or pending edits from another document.
- When a source closes, keep the conversation accessible and indicate the source is unavailable. Offer reopen or an explicit new scope. Do not treat a closed source as permission to apply its proposal to the next document.
- Deleted or changed content invalidates an unsafe pending apply. Retain the source-hash/revalidation checks already in the assistant.
- Existing idea-to-content promotion rules still carry the correct transcript/ledger and leave source-specific pending edits behind.
- Browser and specialized surfaces use the capabilities their context providers actually expose. The UI must not imply it has read inaccessible content.

**Window policy:** one active presentation owner for a conversation. Presentation geometry is window-local; conversation identity is independent of it. The current singleton store is not evidence of safe independent multi-window sessions. In the first supported model, another window reveals or deliberately takes over the existing conversation rather than creating a second writable composer over the same store. A transfer uses an owner token so stale close/open events cannot reclaim ownership.

Closing a window preserves the draft and completed/partial conversation according to the durable session policy. App exit should record an interrupted run; it must not promise background continuation or replay a tool call on restart. Account/workspace switching partitions persisted data and clears transient ownership.

## 8. Coexistence with the rest of Cosmo

| Surface or competing UI | Design decision |
|---|---|
| Canvas, Today, normal document focus | Companion routes to the inline assistant with the correct available context. |
| Inquiry / Deep Dive | Preserve their dedicated copilot/capture workflow. Reveal the appropriate existing surface; suppress a redundant floating entrance when that assistant is already visible. |
| Collaborator / legacy CosmoWindow | Keep explicit routes and their conversation identities until a tested migration exists. Do not silently combine transcripts. |
| Command-K, Settings, onboarding, blocking sheets | Suspend companion hit testing and decorative feedback beneath the foreground flow. Restore without stealing focus. |
| Current bottom-right GlobalStatusPill | Integrate into one placement policy; the two controls may not occupy the same corner. |
| CompanionMomentBanner, task toasts, undo receipts | One feedback host per event. Attach companion moments to the character/chat identity; operational Undo/Review remains available independently. |
| Inspector, scrollbars, resize handles, canvas selection | Treat their bounds as exclusions. Decorative transparent pixels never create a full-window click shield. |
| Full-screen focus/writing | Settle into a quiet or minimal entrance according to preference; critical in-flight state remains reachable. |
| Inactive/occluded/minimized window | Stop decorative drawing and sound; do not open a result over the user’s current application. |
| Popovers, menus and drag sessions | Avoid relocating a target under the pointer. Defer cosmetic position adjustments until the interaction settles. |

A CompanionPlacementPolicy should compute anchors from actual safe content bounds and occupied rectangles. Prefer a stable bottom-right position with deterministic alternate placement when necessary. Use hysteresis to avoid the character hopping around during resize. Persist a semantic preference, not screen pixel coordinates.

The first version should avoid free-roaming behavior and permanent drag handles. Edge-snapped relocation is a later enhancement if actual usage demonstrates a need.

## 9. Growth, rituals and the tutorial

Retain the four earned forms and existing 3/10/30-active-day thresholds. Character choice does not reset growth. Rest days do not cause deterioration. Chatting repeatedly or hovering must not become a way to manufacture progress.

Use successful, identified local activity events. Replayed sync, historical imports, duplicate completions and failed saves do not produce a fresh reward. Batch completions update all genuine progress but coalesce visual feedback.

The tutorial should teach the actual system through a short, resumable path:

1. Choose a character or Minimal appearance, with a clear “change this later.”
2. Open a clearly labeled practice conversation and understand the context chip.
3. Move that same practice conversation into a pane and back. Demonstrate that its draft survives.
4. Create a ritual: WHEN a task is completed / focus session is saved → THEN show a character response or offer a supported next action.
5. Preview locally, then explicitly enable the real ritual. Show where to edit or disable it.

The practice mode does not modify real tasks, start a real focus timer, accrue growth or spend model tokens. Optional real assistant use begins with the user’s own request.

For advanced personalization, bridge to the existing Assistant Studio and automation engine. Start with “offer this skill after this event”; user confirmation starts the skill. Task/focus events need an explicit typed adapter into the existing automation dispatcher, with event IDs, scope, cooldown and duplicate protection. Do not construct a second hidden scheduler inside the companion.

Each automation editor should show: trigger, scope, conditions, action, whether it invokes AI, delivery location, and an honest preview. Expose recent outcomes and a disable control. Scheduled/background behavior must reflect the platform runtime’s actual ability to execute; an app-local timer is not a background scheduling guarantee.

Default rituals remain opt-in. Decoration creates no model calls. A companion animation never signals that a proposed document edit has been applied before the underlying operation succeeds.

## 10. Personalization and preference ownership

| Setting or data | Ownership |
|---|---|
| Selected character, earned growth, supported rituals | Existing account/workspace sync contracts; preserve stable character IDs |
| Companion vs Minimal; preferred compact vs pane opening | Device preference, with clear defaults |
| Motion intensity | Device preference constrained by system Reduce Motion; system setting takes precedence |
| Sound and haptics | Existing SoundEngine/Haptics preferences and platform mute behavior |
| Window location, pane geometry, last presentation | Local window/device state, never raw geometry synced to another screen |
| Draft and reading state | Durable per conversation/workspace; transferred between hosts without duplication |
| Tutorial progress | Resumable; migration must not show a completed user an unavoidable first-run sequence |

Recommended controls are deliberately few: Character/Minimal, opening preference, motion preference, and the existing sound controls. Full hiding is available through an explicit menu/settings choice, while menu and keyboard access remain intact.

Changing character updates future visual expression without changing conversation identity or assistant capabilities. Any optional tone preference affects future responses only; it must not rewrite old messages, remove citations or change tool permissions.

## 11. iPhone: the same identity, different layout

Desktop gets the full corner presence. iPhone gets a compact portrait in existing navigation chrome, with one active entrance per screen. Do not add another floating button beside the existing Create orb.

- Tap opens a native conversation sheet; expand to a full-height reading layout when needed.
- The character becomes the sheet’s header identity; the keyboard, home indicator and tab bar own their safe areas.
- Companion customization remains reachable through the assistant menu and Settings; it is no longer the primary action of the avatar.
- Menus and every portrait control meet a 44-point target, use Dynamic Type, and work without hover.
- Existing capture/create affordances remain recognizable.
- There is no forced desktop pane metaphor on iPhone. A future wider-screen layout can reuse the host contract, but should not imply tablet support that has not been tested.
- A missing API key, denied microphone, offline state or unavailable tool has an explicit repair path. The local companion and earned journey still work.
- Voice is an explicit action. An attentive face does not imply an active microphone.

**Conversation continuity is a separate gate.** Define a versioned interchange envelope with stable IDs, scope, messages, source references, completed tool receipts and compatible review state. Import from Mac surface-session archives and iPhone agent-conversation atoms without deleting either original. Unsupported/pending actions remain readable with an honest limitation; they are not replayed or shown as executable on a platform that lacks the required tool.

Until this migration is tested, promise shared companion identity/growth/rituals—not seamless cross-device chat history. Do not revive the dormant phone chat tab by simply adding a portrait button and call it parity.

## 12. Engineering structure

Proposed components, names provisional:

| Component | Responsibility |
|---|---|
| CompanionAssistantCoordinator | Typed open/close/compact/pane requests, host ownership, focus restoration and handoff outcome |
| CompanionPresenceModel | Narrow, equality-checked projection of phase, pending attention, growth, motion policy and optional voice status |
| CompanionPlacementPolicy | Safe geometry, exclusion regions, blocking surfaces and stable anchor selection |
| CompanionCharacterDefinition / Rig / Pose | Authored character geometry, growth attachments, optical bounds and expression controls |
| CompanionCharacterView | Local rendering; never subscribes to the entire transcript |
| CompanionDockView | One accessible launcher with explicit mode, tooltip, keyboard focus and menu |
| AssistantConversationSurface | Shared transcript, context, review and composer content independent of window/pane chrome |
| CompanionQuickChatHost | Compact chrome and adaptive sizing around that shared content |
| AssistantPresentationSnapshot | Session key, draft/caret, source selection, scroll anchor and follow state during transfer |
| CompanionEventAdapter | Deduplicated saved-task/focus/review events routed into local feedback and supported automations |
| ConversationInterchangeAdapter | Versioned cross-platform imports, compatibility checks and durable fallback for unsupported content |

Main integration work:

- MainView: replace the center entrance under a feature flag; mount independent review and feedback hosts.
- MainNotificationRouter: distinguish explicit pane requests from “ensure an answer is visible.”
- PaneManager: return opened/activated/full/unavailable outcomes; preserve existing stable IDs, pins and seat behavior.
- CosmoInlineAssistantStore: retain agent and session ownership; add draft persistence and presentation-neutral event requests. Avoid an unrelated full-store rewrite.
- CosmoInlineAssistantPaneView and composer: extract shared content while retaining deck tab chrome and current rendering safeguards.
- CompanionStore: retain existing identity/journey data; expose small, typed saved-event notifications rather than driving layout.
- Specialized assistant routes: audit and map each caller before retiring legacy visibility paths.
- iPhone RootTabView/Today/settings/chat model: add the supported entrance and migrate conversation contracts deliberately.
- SoundEngine: one cue owner per operation, with no autoplay on idle or hover.

The legacy “pane requested” boolean needs a typed compatibility bridge. Every current writer—normal answer, streaming answer, riff, canvas plan, inquiry proposal, explicit shortcut—must be classified. Otherwise one missed path can reopen the pane underneath compact chat.

## 13. Edge-case acceptance matrix

| Case | Required acceptance behavior |
|---|---|
| Rapid double-click / repeated shortcut | One host and no duplicate pane or submission |
| Open then immediately close | No orphaned hit region, invisible key responder or delayed reopen |
| Move to pane during streaming | Same request and stream; no repeated answer or lost tokens |
| Close during streaming | Run continues according to its existing lifetime; Stop remains an explicit action |
| Stop after tools already ran | Preserve completed receipts; “Stopped” does not imply that earlier changes were undone |
| Draft with attachments, skill and selected text | Transfer preserves all intent; scope remains explicit |
| IME composition, dictation or marked text | Defer automatic rehosting; explicit moves follow native composition/focus handling without lost or duplicated text |
| User reading an old message | Resize/transfer restores a message anchor; streaming does not drag them to the bottom |
| Six panes / pinned panes / hidden assistant tab | No silent failure, eviction or duplicate; recoverable route remains visible |
| Window resize, monitor move, display scaling | Recompute bounds; no offscreen launcher or cropped conversation |
| Source closes, is deleted or changes during a run | Keep transcript; revalidate actions and explain unavailable context |
| Another document gains focus while drafting/reviewing | No silent retarget or draft erasure |
| Idea promoted to content | Retain existing promotion-carry semantics; source-specific pending edits stay with their source |
| Two windows act on the same conversation | One presentation owner; stale callbacks cannot steal it |
| App loses focus or window is occluded | No decorative loop or unsolicited popup over another app |
| App quit/crash during a draft/run | Durable draft/partial history; interrupted status, no blind replay of side effects |
| Companion switched mid-run or mid-milestone | Conversation is unchanged; appearance settles to the latest selection |
| Growth sync arrives while typing | Update retained progress; defer or skip visual celebration |
| Imported/replayed/batched activity | Count valid history without replaying every celebration |
| Missing/corrupt art or unknown character ID | Valid fallback portrait and functional assistant button |
| Unreadable persisted session | Preserve the original blob; no empty overwrite |
| Account/workspace switch or sign-out | No conversation, draft, animation or attachment leaks across identities |
| Offline, auth expired, rate-limited or service failure | Local companion remains useful; retry does not duplicate a successful tool action |
| Denied microphone / voice interrupted | Clear actual mic state, visible repair/stop action, working text path |
| Reduce Motion, Still, contrast, transparency | Same capabilities with nonanimated/readable states |
| VoiceOver, keyboard-only, Switch Control | Discoverable button, meaningful labels, logical focus order and no hover dependency |
| Large text, long localization, RTL | Controls remain reachable; anchor and reading direction are deliberate |
| Command-K, Settings, menus, welcome gate | Correct foreground priority; no character stealing clicks or focus |
| Task completion sound and companion reaction coincide | Exactly one intended audible/tactile reward |
| Pane mode selected in preferences | Direct pane route continues working even when character artwork is disabled |
| Feature disabled or rolled back | Existing conversations, growth, rituals and drafts remain readable and preserved |

## 14. Verification and the quality bar

**Art gate:** approve the three-character proof at real interface size on dense Canvas, Today, an editor and an open pane. Review silhouettes, optical balance, dark/mono themes and all growth forms before completing the other nine. Deliver contact sheets and short motion reels.

**Interaction gate:** exercise the whole resting → compact → streaming → pane → compact → closed path with the same real session. A polished opening animation cannot compensate for one lost draft.

**Correctness gate:** focused tests for the coordinator reducer, capacity outcomes, ownership races, draft restoration, context pinning, duplicate events, partial results, permission states and schema migration. Reuse the existing routing, streaming, scroll-follow, pane, promotion-carry and growth tests.

**Performance gate:** baseline on a representative lower-end supported Mac and iPhone. Proposed budgets: local visual acknowledgment within 100 ms; no recurring animation work while resting/hidden; target at most about 1 ms of additional per-frame rendering work during a character gesture on the baseline device; no material scroll/resize regression against the same scene with the companion disabled. Measure rather than infer. Preserve smooth 60 Hz interaction and exploit 120 Hz where the existing view/device supports it.

**Accessibility gate:** complete core flows with Reduce Motion, large text, VoiceOver and keyboard alone. Check real mic status and every icon-only control. No state relies solely on hue, sound or character emotion.

**Everyday-use gate:** conduct normal writing and planning sessions, not only demonstrations. Measure discoverability, unwanted interruptions, mistaken scope, accidental activation and how often users switch to Minimal. Success is useful access to AI and uninterrupted work—not extra clicks on the character.

**Release evidence:** clean builds from fixed revisions, isolated DerivedData/simulators when other work is running, before/after captures for all hosts, a regression matrix, and a recorded list of any unresolved gaps. The concurrent build/disk failures encountered in the earlier companion work must not become the verification process for this release.

## 15. Delivery sequence

| Phase | Deliverable | Exit gate |
|---|---|---|
| 1. Architecture contract | Typed presentation intent, scope/owner rules, transfer snapshot, capacity outcome, draft persistence design | All current assistant entry points classified; no ambiguous “open pane” path |
| 2. Art and motion proof | Pip, Juniper and Scout; actual-size stills and core gestures in a realistic shell | One art direction accepted against the visual and attention criteria |
| 3. Desktop vertical slice | Resting launcher, complete compact chat, dock/undock, existing pane behavior | One real conversation survives every transition, including streaming and a full deck |
| 4. Full cast and feedback | Twelve rigs, four forms each, bounded reactions, sound coordination and fallback art | No repetitive shared-bounce feel; growth and event deduplication checks pass |
| 5. Tutorial and personalization | Practice handoff, editable rituals, Studio bridge and migration of presentation preferences | A new user can discover AI, move to a pane and create a ritual without assistance |
| 6. iPhone and continuity | Compact native entry/sheet; explicit service and conversation compatibility work | Real device flows pass; cross-device history claimed only after migration tests pass |
| 7. Hardening and rollout | Accessibility/performance sweeps, dense-workspace testing, feature flag and rollback | Builds and evidence complete; no known draft-loss, duplicate-run, scope or hit-testing defect |

Art proof and architecture investigation can advance together, but the complete cast should follow the three-character proof, and broad rollout should follow a proven vertical slice.

For existing users, offer a short one-time introduction and a reversible appearance choice. Preserve their character, growth and rituals. Keep the old entrance behind an internal rollback flag until the new flow is verified, without exposing both launchers at once.

## 16. What we deliberately defer

Free-roaming desktop behavior, movement across unrelated apps, voice wake words, multiple simultaneous writable views of one chat, generated costumes at runtime, rewards for model usage, and a separate companion automation runtime.

These are not prerequisites for an excellent companion. The first release should be complete at the things users will do every day: find their assistant, ask in context, move the same chat into a pane, keep their work, and enjoy a character that belongs in Cosmo.
