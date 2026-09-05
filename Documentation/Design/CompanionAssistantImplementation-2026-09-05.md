# Companion assistant implementation

Implemented 5 September 2026 in the Mac and iPhone checkouts. The earlier [design plan](CompanionAssistantPlan-2026-09-05.md) records the intended direction; this document distinguishes the delivered behavior from validation still required before a broad release.

## The experience

The selected companion opens Cosmo. All twelve existing identities remain: Pip, Fiddle, Delia, Otto, Morel, Juniper, Clementine, Luna, Sol, Sable, Wallace and Scout. They share assistant capabilities while retaining their individual appearance, growth details and celebration copy.

On Mac, the corner character opens compact chat. The pane button moves that conversation into the current pane deck; the pane header returns it to the corner. The existing Option-A shortcut still opens the pane directly. An existing assistant tab is revealed instead of duplicated. Six occupied panes leave compact chat available with an explanation.

On iPhone, a 44-point portrait in navigation chrome opens a native medium/large conversation sheet. Today, Spaces, Inbox, Swipes and Content all expose it. The Create control remains in place. The header portrait opens the companion world, while history and close have explicit controls.

## Art and attention

- Resolution-independent native artwork for twelve characters × four forms. The cast gallery previews earned and future forms without awarding activity.
- Resting, attentive, working, speaking, reviewing, celebrating and focus-rest expressions. Character-specific pose adjustments respond to meaningful state changes.
- Brief gestures settle after 360–700 ms. There is no idle animation timer and no per-token character animation. System Reduce Motion, quiet movement and inactive scene state constrain motion.
- Growth changes are crossfaded. Earned progress never decays; switching characters retains it. Activity comes from saved task/focus records, not AI usage.
- Companion messages expire after eight seconds. Hidden celebrations do not replay much later. Operational review and work status remain separate from decorative feedback.
- Character or Minimal appearance, quiet movement, preferred pane opening and a hideable Mac entrance are local presentation preferences. Hidden entrance access is recoverable in Assistant settings; Option-A remains available.

The full [native artwork contact sheet](/Users/euanspencer/.codex/visualizations/2026/09/05/01a0704b-9046-7443-ab4e-fed17853e030/companion-evolution.png) is rendered from the actual character code.

## One conversation, two Mac hosts

`CompanionAssistantCoordinator` owns resting/compact/pane presentation and the active window. `CosmoInlineAssistantStore` continues to own the request, stream, messages, source context, skills and review state. `AssistantConversationSurface` supplies the same transcript and composer in both hosts.

Transfers retain the actual native NSTextView/NSScrollView, including its attachment storage and undo manager. Composer text and selection also live with the store and are durably saved. Native IME marked text blocks rehosting until composition finishes. Selection offsets are bounded safely, including corrupt integer offsets.

Passive document focus cannot displace an unsent draft, held presentation, active run or pending review. Explicit scope changes save the outgoing conversation. A closed source is reported before submission. A user dismissal outranks automatic visibility requests from the same ongoing run. Closing chat is separate from Stop.

The reader's visible message anchor and follow-latest preference survive host changes. Empty chat begins at its heading. There is one writable presentation owner across Mac windows; another window can reveal or explicitly take over the conversation. The shared editor is not independently editable in two windows.

The former centered entrance is replaced by the corner host. Global work status is placed in the same vertical corner stack. Settings, Command-K, Inquiry and Deep Dive suppress the redundant entrance. The compact panel observes outside clicks without consuming the workspace click, and menus are dismissed before chat.

## Assistant surfaces

The redesigned pane and compact chat retain the existing context selector, mention composer, skill picker, Studio, review actions, receipts, follow-up actions and streamed answer renderer. New empty states use the Greenhouse editorial typography and three relevant starters; general context does not imply an open draft. Starters fill the composer and do not submit.

The iPhone model belongs to AppModel rather than a transient sheet. Dismissing the sheet preserves its conversation, draft and active request. Local checkpoints are partitioned by signed-in identity. History can reopen local conversations; interrupted or failed runs preserve partial text. Missing model configuration has a Settings route, and local companion interactions still work.

## Tutorials and personalization

The Assistant tab explains the relationship between the companion and Cosmo. A local practice conversation teaches open, expand, return and close with a preserved editable draft. It spends no tokens and changes no tasks or growth. Its instructions differ between Mac and iPhone.

The ritual lesson uses the real saved-task or saved-focus event, previews the chosen response locally and requires an explicit Enable action. Rituals remain opt-in, editable and disableable. Mac also links to the existing Assistant Studio for skill creation. The companion does not introduce a second scheduler or claim iPhone background execution. Advanced arbitrary event-to-skill automation is not added by this integration.

## Conversation exchange: explicit continuation

Mac and iPhone can publish readable user/assistant messages to a versioned `companion_conversation` system-event envelope through the existing library sync path. Records have stable origin/conversation/message IDs. Merge retains both message sets; unsupported records are not overwritten. Originals remain in their native archives.

Choosing Continue creates a new local conversation with a provenance notice. It does **not** move executable tools, pending proposals, native document context or draft state to the other platform. Original receipts and pending edits remain at the source. Cross-device end-to-end sync has not been tested with an authenticated account; this is not a claim of seamless live session handoff.

## Validation

- Mac Debug build: passed, isolated DerivedData, arm64, code signing disabled for the local build.
- iPhone simulator Debug build: passed, iPhone 17 Pro / iOS 26.1, isolated simulator and DerivedData.
- Ten native continuity tests: draft/caret restoration, full deck, legacy pane identity, stream/draft transfer, dismissed-run behavior, passive scope retention, clearing a saved draft, corrupt selection offsets, compact bounds and portable-message merge.
- Twenty-five existing regression checks against the built app module: journey, pane activation, promotion carry, streaming and scroll follow. These are the synchronous XCTest methods exercised by the native harness, not the full repository test suite.
- Native Mac component walkthrough: compact → pane → compact → close → reopen retained the exact unsent draft. Production views and the actual compiled app module were used in an isolated review app with a mock conversation store.
- Native iPhone walkthrough: medium/large sheet, starter prefill, dismissal/reopening and process relaunch preserve the draft. Missing-key UI remains usable. Earlier journey walkthroughs cover cast selection, form preview, real rituals and focus-session guards.

Live model requests and tool application were not exercised during this review. Real-device performance budgets, a complete VoiceOver/Dynamic Type/RTL sweep, multiple-window race stress, authenticated cross-device synchronization and long everyday writing sessions remain release validation. No claim of measured 120 Hz performance, full account-migration coverage or an award is made.

The workspace contains concurrent changes from other tasks. No commit or deployment was made; other changes were preserved. Two call-site API mismatches in the concurrent Spaces navigator were aligned with the existing SidebarRow and ProMotionSprings APIs to unblock the combined Mac build.
