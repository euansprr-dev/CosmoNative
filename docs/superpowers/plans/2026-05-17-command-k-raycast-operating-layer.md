# Command K Raycast Operating Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Cosmo Command K into a Raycast-grade object operating layer for actions, capture, swipes, inquiries, tasks, quicklinks, clips, snippets, and recipes without duplicating Command A's AI chat role.

**Architecture:** Keep the existing master/detail shell and selection model, then add a typed contextual action system around it. The system resolves the current selection and query into `CommandKActionContext`, asks a registry for available actions, renders those actions in the bottom bar and searchable Action Panel, and executes through a narrow executor that posts existing notifications or calls existing services.

**Tech Stack:** macOS SwiftUI, existing `DS` design tokens, `NotificationCenter`, `AtomRepository`, `AgentToolExecutor`, `SwipeFileEngine`, `QuickCaptureProcessor`, `InquiryRepository`, file-backed Codable stores for user commands, and XCTest through `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build`.

---

## The Moment

The user opens Command K, selects anything in Cosmo, sees exactly what it is, and can act on it without leaving the keyboard: open, capture, attach, convert, schedule, crystallize, or run a saved workflow.

## Visual Layout

Primary shell stays calm and already mostly exists:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│  ⌕ Search your mind...                         [ All types ▾ ] [ mic ] ⌘K  │
├───────────────────────────────┬─────────────────────────────────────────────┤
│ RECENTS / RESULTS / DOMAIN    │ PREVIEW                                     │
│                               │                                             │
│  ▸ My best-kept secret...     │  ┌───────────────────────────────────────┐  │
│    Research · 3d              │  │ Swipe video / carousel / note / cover │  │
│                               │  └───────────────────────────────────────┘  │
│    Thousands of vets...       │                                             │
│    Research · 4d              │  Title                                      │
│                               │  INFORMATION                                │
│    Create task: ...           │  Type      Research                         │
│                               │  Links     1 connected                      │
├───────────────────────────────┴─────────────────────────────────────────────┤
│ Command K                 Open ↵    ·    Actions ⌘K    ·    Pin ⇧⌘P        │
└─────────────────────────────────────────────────────────────────────────────┘
```

Action Panel becomes the real operating surface:

```text
┌───────────────────────────────────────────────────────────────┐
│ Actions for "My best-kept secret..."                          │
│ ⌕ Search actions...                                           │
├───────────────────────────────────────────────────────────────┤
│ PRIMARY                                                       │
│ ↵  Open in Focus Mode                                         │
│                                                               │
│ SWIPE                                                         │
│ ⌘S  Open Swipe Study                                          │
│     Analyze Hook                                              │
│     Use as Blueprint for Current Draft                        │
│     Create Idea from Swipe                                    │
│                                                               │
│ INQUIRY                                                       │
│     Add to Active Inquiry                                     │
│     Start Inquiry on This                                     │
│                                                               │
│ COMMAND CENTER                                                │
│     Create Review Task                                        │
└───────────────────────────────────────────────────────────────┘
```

Inline forms are compact, not modal:

```text
┌───────────────────────────────────────────────────────────────┐
│ Capture Swipe                                                 │
│ URL        https://www.instagram.com/reel/...                  │
│ Client     [ Optional client ▾ ]                               │
│ Attach to  [ Current draft ▾ ]                                 │
│ Analyze    [x] Hook  [x] Format  [ ] Transcript                │
├───────────────────────────────────────────────────────────────┤
│ Command K                         Capture ↵    ·    Cancel Esc │
└───────────────────────────────────────────────────────────────┘
```

## Design Rationale

- The rail remains dense because Command K is a repeated-use tool, not a marketing page.
- The preview is the confidence surface: it shows enough of the selected object to act without opening it.
- Accent color is punctuation only: selected row, primary action, action category glyphs.
- The action panel is searchable and grouped, mirroring Raycast's strongest pattern while retaining Cosmo's vellum/glass language.
- Forms appear inside the same shell so creation and capture feel like command execution, not navigation.

## Motion

- Opening Command K: existing panel entrance remains.
- Moving selection: preview crossfades quickly with stable frame dimensions; media should not resize the shell.
- Opening Action Panel: scale from `0.98` to `1.0` and fade in using the project's spring policy.
- Executing an action: bottom bar primary label switches to `Working...`; on success the shell closes or hides based on the action contract.
- Form validation: disabled primary action stays visible with a concise bottom-bar reason.

## Hard Product Constraints

- Command A remains the AI chat surface. Command K may run AI-backed actions, but it must not become a generic chat prompt.
- Every action must have a keyboard path and a visible menu path.
- Single click selects/previews. `Enter`, double-click, or an explicit action opens/executes.
- No raw colors in new SwiftUI views. Use `DS` tokens and existing Command K chrome.
- No new database migrations for the first implementation wave unless a task explicitly calls for one. User command data starts as file-backed Codable state.
- Preserve existing dirty work. At plan creation time, these files had uncommitted changes: `Tests/CosmoOSTests/CommandKSearchPipelineTests.swift`, `UI/CommandK/CommandKViewModel.swift`, `UI/CommandK/CortexDetailPane.swift`.

## Feature Coverage Matrix

| Feature | Tasks |
| --- | --- |
| Universal Object Action Panel | Tasks 1, 2, 3, 13 |
| Command K Capture Router | Tasks 4, 5, 13 |
| Swipe-specific action set | Tasks 6, 7, 13 |
| Command K Forms | Task 4 |
| Cosmo Quicklinks | Task 10 |
| Memory Clipboard / Clips | Task 11 |
| Snippets + Templates | Task 12 |
| Inquiry command surface | Task 8 |
| Command Center bridge | Task 9 |
| Action Recipes | Task 14 |

## File Structure

Create:

- `UI/CommandK/Actions/CommandKActionContext.swift`  
  Builds a typed context from query, current `CortexDetailSubject`, hydrated `Atom`, active domain, and active app state.
- `UI/CommandK/Actions/CommandKContextualAction.swift`  
  Value model for action identity, category, title, subtitle, icon, shortcut, role, availability, and executable intent.
- `UI/CommandK/Actions/CommandKActionRegistry.swift`  
  Pure registry that returns grouped actions for a context.
- `UI/CommandK/Actions/CommandKActionExecutor.swift`  
  Side-effect boundary for notifications, repository calls, `AgentToolExecutor`, `SwipeFileEngine`, and `QuickCaptureProcessor`.
- `UI/CommandK/Actions/CommandKActionPanel.swift`  
  Searchable Raycast-style action panel rendered from registry groups.
- `UI/CommandK/Actions/CommandKActionPanelRow.swift`  
  Focusable row for an action, with shortcut and role styling.
- `UI/CommandK/Forms/CommandKFormModel.swift`  
  Form kinds, field model, validation, and resolved execution intents.
- `UI/CommandK/Forms/CommandKInlineFormView.swift`  
  Shared inline form renderer for capture, task, idea, inquiry, quicklink, snippet, and recipe forms.
- `UI/CommandK/Capture/CommandKCaptureRouter.swift`  
  Turns query or pasted content into a capture preview and execution intent.
- `UI/CommandK/Capture/CommandKCapturePreview.swift`  
  Small typed preview model for URL/text capture.
- `UI/CommandK/UserCommands/CommandKUserCommandModels.swift`  
  `CommandKQuicklink`, `CommandKMemoryClip`, `CommandKSnippet`, `CommandKActionRecipe`, and shared IDs.
- `UI/CommandK/UserCommands/CommandKUserCommandStore.swift`  
  File-backed Codable actor for quicklinks, clips, snippets, templates, and recipes.
- `UI/CommandK/UserCommands/CommandKUserCommandSearchComposer.swift`  
  Converts saved user commands into searchable `CommandKAction` or `UnifiedSearchResult`-like rows.
- `UI/CommandK/Recipes/CommandKRecipeRunner.swift`  
  Executes validated multi-step action recipes through `CommandKActionExecutor`.
- `Tests/CosmoOSTests/CommandKActionRegistryTests.swift`
- `Tests/CosmoOSTests/CommandKActionExecutorTests.swift`
- `Tests/CosmoOSTests/CommandKFormModelTests.swift`
- `Tests/CosmoOSTests/CommandKCaptureRouterTests.swift`
- `Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift`
- `Tests/CosmoOSTests/CommandKRecipeRunnerTests.swift`

Modify:

- `UI/CommandK/CortexActionsMenu.swift`  
  Replace fixed `Menu` content with the new searchable action panel entry point while keeping fallback native menu support where useful.
- `UI/CommandK/CortexActionBar.swift`  
  Show primary action from registry, action panel button, pinned action hint, and disabled reason.
- `UI/CommandK/CortexMasterDetailView.swift`  
  Construct `CommandKActionContext` and provide it to action bar/panel.
- `UI/CommandK/CortexDetailPane.swift`  
  Expose selected hydrated atom to context and keep swipe media preview stable.
- `UI/CommandK/CortexResultRail.swift`  
  Add rows for user commands, clips, snippets, quicklinks, forms, and recipes where query demands them.
- `UI/CommandK/CommandKView.swift`  
  Add action panel presentation state and route `⌘K` while Command K is open to the action panel.
- `UI/CommandK/CommandKViewModel.swift`  
  Hold current inline form, user command search results, action context cache, and primary contextual action state.
- `UI/CommandK/CommandKSearchPipeline.swift`  
  Extend parsing to route command-form prefixes and saved quicklinks without generic AI chat.
- `Core/CosmoNotifications.swift`  
  Add narrowly typed notification names only where existing notifications are insufficient.
- `Core/CosmoApp.swift`  
  Surface high-value actions in native macOS Commands after the core action registry exists.
- `Canvas/CommandCenter/CommandCenterTaskMenus.swift`  
  Reuse Command K task action intents for task row context menus if the implementation reveals duplication.

## Test Command Reference

Use targeted tests during implementation:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKCaptureRouterTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKUserCommandStoreTests test
```

Use the full build gate before handoff:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

If the known unrelated `CosmoVoiceDaemon` / `MLXEmbedders.ModelContainer` issue still blocks builds, record the exact compiler output and continue only with targeted tests that do not hit that target.

---

### Task 0: Execution Setup and Baseline

**Files:**
- Read: `UI/CommandK/CommandKView.swift`
- Read: `UI/CommandK/CommandKViewModel.swift`
- Read: `UI/CommandK/CortexMasterDetailView.swift`
- Read: `UI/CommandK/CortexActionsMenu.swift`
- Read: `UI/CommandK/CortexActionBar.swift`
- Read: `UI/CommandK/CommandKSearchPipeline.swift`
- Read: `Core/CosmoNotifications.swift`

- [ ] **Step 1: Create an isolated execution branch or worktree**

```bash
git status --short
git switch -c codex/command-k-raycast-operating-layer
```

Expected: branch created; existing user changes remain visible and must not be reverted.

- [ ] **Step 2: Capture baseline targeted tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKSearchPipelineTests test
```

Expected: either PASS, or a specific pre-existing compile failure recorded in the task notes.

- [ ] **Step 3: Capture baseline build gate**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: PASS, or the known unrelated build blocker with exact error text recorded.

- [ ] **Step 4: Commit only if setup created no code changes**

No commit is required for a branch-only setup. If environment files were generated by tools, inspect and commit only intentional files.

---

### Task 1: Define the Contextual Action Model

**Files:**
- Create: `UI/CommandK/Actions/CommandKActionContext.swift`
- Create: `UI/CommandK/Actions/CommandKContextualAction.swift`
- Test: `Tests/CosmoOSTests/CommandKActionRegistryTests.swift`

- [ ] **Step 1: Write failing model tests**

Add:

```swift
import XCTest
@testable import CosmoOS

final class CommandKActionRegistryTests: XCTestCase {
    func testSwipeContextExposesSwipeCapabilities() {
        let subject = CortexDetailSubject.swipe(
            SwipeGalleryItem(
                atomUUID: "swipe-1",
                title: "Property Hook",
                hookText: "Buy near a military base",
                hookScore: 8.4,
                platform: "instagram",
                thumbnailUrl: "https://example.com/thumb.jpg",
                author: "creator"
            )
        )

        let context = CommandKActionContext(
            query: "",
            subject: subject,
            hydratedAtom: nil,
            mode: .compact,
            activeInquirySessionUUID: "session-1",
            activeContentDraftUUID: "content-1"
        )

        XCTAssertEqual(context.selectionKind, .swipe)
        XCTAssertEqual(context.selectedAtomUUID, "swipe-1")
        XCTAssertTrue(context.hasActiveInquirySession)
        XCTAssertTrue(context.hasActiveContentDraft)
    }

    func testActionIdentityIsStableAcrossTitleChanges() {
        let first = CommandKContextualAction(
            id: .openFocusMode,
            category: .primary,
            title: "Open",
            subtitle: nil,
            systemImage: "arrow.up.left.and.arrow.down.right",
            shortcut: .returnKey,
            role: .normal,
            availability: .enabled,
            intent: .openAtom(uuid: "atom-1")
        )
        let second = first.withTitle("Open in Focus Mode")

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.intent, second.intent)
        XCTAssertEqual(second.title, "Open in Focus Mode")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
```

Expected: FAIL because `CommandKActionContext` and `CommandKContextualAction` do not exist.

- [ ] **Step 3: Implement action context**

Create `CommandKActionContext.swift`:

```swift
import Foundation

enum CommandKSelectionKind: Equatable {
    case none
    case atom(AtomType)
    case swipe
    case idea
    case readwise
    case thinkspace
}

struct CommandKActionContext: Equatable {
    let query: String
    let subject: CortexDetailSubject
    let hydratedAtom: Atom?
    let mode: CortexMode
    let activeInquirySessionUUID: String?
    let activeContentDraftUUID: String?

    var selectedAtomUUID: String? {
        subject.atomUUID ?? hydratedAtom?.uuid
    }

    var selectionKind: CommandKSelectionKind {
        switch subject {
        case .empty:
            return .none
        case .swipe:
            return .swipe
        case .idea:
            return .idea
        case .readwise:
            return .readwise
        case .library(let item):
            if item.kind == .thinkspace { return .thinkspace }
            return item.atomType.map(CommandKSelectionKind.atom) ?? .none
        case .recent(let item):
            return .atom(item.type)
        case .result(let result):
            if result.resultKind == .thinkspace { return .thinkspace }
            return result.atomType.map(CommandKSelectionKind.atom) ?? .none
        }
    }

    var hasActiveInquirySession: Bool {
        activeInquirySessionUUID?.isEmpty == false
    }

    var hasActiveContentDraft: Bool {
        activeContentDraftUUID?.isEmpty == false
    }
}
```

- [ ] **Step 4: Implement contextual action value types**

Create `CommandKContextualAction.swift`:

```swift
import Foundation

enum CommandKContextualActionID: String, Codable, Hashable, CaseIterable {
    case openFocusMode
    case openAsPane
    case addToCanvas
    case goToObject
    case deleteObject
    case copyCosmoLink
    case openSwipeStudy
    case analyzeSwipeHook
    case attachSwipeToCurrentDraft
    case useSwipeAsBlueprint
    case createIdeaFromSwipe
    case findSimilarSwipes
    case batchReprocessSwipeMedia
    case addToActiveInquiry
    case startInquiryOnSelection
    case refreshInquirySources
    case crystallizeInquiry
    case createTaskFromSelection
    case startFocusTask
    case markTaskDone
    case deferTask
    case scheduleTaskTomorrow
    case runQuicklink
    case runMemoryClip
    case runSnippet
    case runRecipe
}

enum CommandKActionCategory: String, Codable, Equatable, CaseIterable {
    case primary = "Primary"
    case object = "Object"
    case capture = "Capture"
    case swipe = "Swipe"
    case inquiry = "Inquiry"
    case commandCenter = "Command Center"
    case userCommand = "User Commands"
    case destructive = "Danger"
}

enum CommandKActionAvailability: Equatable {
    case enabled
    case disabled(reason: String)

    var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }
}

enum CommandKActionShortcut: String, Codable, Equatable {
    case returnKey
    case commandK
    case commandS
    case commandI
    case commandT
    case shiftCommandP
}

enum CommandKActionRole: String, Codable, Equatable {
    case normal
    case destructive
}

enum CommandKActionIntent: Equatable {
    case openAtom(uuid: String)
    case openAsPane(uuid: String)
    case addToCanvas(uuid: String)
    case goToObject(uuid: String)
    case deleteAtom(uuid: String)
    case copyCosmoLink(uuid: String)
    case executeTool(name: String, arguments: [String: String])
    case postNotification(name: Notification.Name, userInfo: [String: String])
    case startInquiry(anchorUUID: String, anchorType: String)
    case commandCenter(CommandKCommandCenterIntent)
    case userCommand(id: String)
    case recipe(id: String)
}

enum CommandKCommandCenterIntent: Equatable {
    case createReviewTask(sourceUUID: String)
    case startFocus(taskUUID: String)
    case markDone(taskUUID: String)
    case defer(taskUUID: String, days: Int)
    case scheduleTomorrow(taskUUID: String)
}

struct CommandKContextualAction: Identifiable, Equatable {
    let id: CommandKContextualActionID
    let category: CommandKActionCategory
    let title: String
    let subtitle: String?
    let systemImage: String
    let shortcut: CommandKActionShortcut?
    let role: CommandKActionRole
    let availability: CommandKActionAvailability
    let intent: CommandKActionIntent

    func withTitle(_ title: String) -> CommandKContextualAction {
        CommandKContextualAction(
            id: id,
            category: category,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            shortcut: shortcut,
            role: role,
            availability: availability,
            intent: intent
        )
    }
}
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
```

Expected: PASS for the two model tests.

- [ ] **Step 6: Commit**

```bash
git add UI/CommandK/Actions/CommandKActionContext.swift UI/CommandK/Actions/CommandKContextualAction.swift Tests/CosmoOSTests/CommandKActionRegistryTests.swift
git commit -m "feat: add command k contextual action model"
```

---

### Task 2: Build the Pure Action Registry

**Files:**
- Create: `UI/CommandK/Actions/CommandKActionRegistry.swift`
- Modify: `Tests/CosmoOSTests/CommandKActionRegistryTests.swift`

- [ ] **Step 1: Add failing registry tests**

Append:

```swift
func testRegistryReturnsUniversalObjectActionsForAtomSelection() {
    let subject = CortexDetailSubject.recent(
        RecentDisplayItem(
            id: "atom-1",
            title: "Launch Notes",
            type: .research,
            entityId: 42,
            relativeDate: "2h",
            thumbnailURL: nil,
            preview: "Notes"
        )
    )
    let context = CommandKActionContext(
        query: "",
        subject: subject,
        hydratedAtom: nil,
        mode: .compact,
        activeInquirySessionUUID: nil,
        activeContentDraftUUID: nil
    )

    let actions = CommandKActionRegistry().actions(for: context)
    let ids = actions.map(\.id)

    XCTAssertEqual(ids.first, .openFocusMode)
    XCTAssertTrue(ids.contains(.openAsPane))
    XCTAssertTrue(ids.contains(.addToCanvas))
    XCTAssertTrue(ids.contains(.goToObject))
    XCTAssertTrue(ids.contains(.copyCosmoLink))
}

func testRegistryDisablesInquiryAttachWhenNoActiveInquiryExists() {
    let subject = CortexDetailSubject.recent(
        RecentDisplayItem(
            id: "atom-1",
            title: "Source",
            type: .research,
            entityId: 1,
            relativeDate: "1d",
            thumbnailURL: nil,
            preview: nil
        )
    )
    let context = CommandKActionContext(
        query: "",
        subject: subject,
        hydratedAtom: nil,
        mode: .compact,
        activeInquirySessionUUID: nil,
        activeContentDraftUUID: nil
    )

    let action = CommandKActionRegistry().actions(for: context).first { $0.id == .addToActiveInquiry }

    XCTAssertEqual(action?.availability, .disabled(reason: "No active inquiry session"))
}

func testRegistryReturnsSwipeActionsForSwipeSelection() {
    let subject = CortexDetailSubject.swipe(
        SwipeGalleryItem(
            atomUUID: "swipe-1",
            title: "Swipe",
            hookText: "Hook",
            hookScore: 8,
            platform: "instagram",
            thumbnailUrl: nil,
            author: nil
        )
    )
    let context = CommandKActionContext(
        query: "",
        subject: subject,
        hydratedAtom: nil,
        mode: .expandedDomain(.swipeGallery),
        activeInquirySessionUUID: "inquiry-1",
        activeContentDraftUUID: "content-1"
    )

    let actions = CommandKActionRegistry().actions(for: context)
    let ids = actions.map(\.id)

    XCTAssertTrue(ids.contains(.openSwipeStudy))
    XCTAssertTrue(ids.contains(.analyzeSwipeHook))
    XCTAssertTrue(ids.contains(.attachSwipeToCurrentDraft))
    XCTAssertTrue(ids.contains(.useSwipeAsBlueprint))
    XCTAssertTrue(ids.contains(.createIdeaFromSwipe))
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
```

Expected: FAIL because `CommandKActionRegistry` does not exist.

- [ ] **Step 3: Implement registry grouping and universal actions**

Create `CommandKActionRegistry.swift`:

```swift
import Foundation

struct CommandKActionRegistry {
    func actions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        var actions: [CommandKContextualAction] = []
        actions.append(contentsOf: universalActions(for: context))
        actions.append(contentsOf: swipeActions(for: context))
        actions.append(contentsOf: inquiryActions(for: context))
        actions.append(contentsOf: commandCenterActions(for: context))
        return actions
    }

    func groupedActions(for context: CommandKActionContext) -> [(category: CommandKActionCategory, actions: [CommandKContextualAction])] {
        let actions = actions(for: context)
        return CommandKActionCategory.allCases.compactMap { category in
            let section = actions.filter { $0.category == category }
            return section.isEmpty ? nil : (category, section)
        }
    }

    private func universalActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        guard let uuid = context.selectedAtomUUID else { return [] }
        return [
            .init(id: .openFocusMode, category: .primary, title: "Open in Focus Mode", subtitle: nil, systemImage: "arrow.up.left.and.arrow.down.right", shortcut: .returnKey, role: .normal, availability: .enabled, intent: .openAtom(uuid: uuid)),
            .init(id: .openAsPane, category: .object, title: "Open as Pane", subtitle: nil, systemImage: "rectangle.split.2x1", shortcut: nil, role: .normal, availability: .enabled, intent: .openAsPane(uuid: uuid)),
            .init(id: .addToCanvas, category: .object, title: "Add to Canvas", subtitle: nil, systemImage: "plus.rectangle.on.rectangle", shortcut: nil, role: .normal, availability: .enabled, intent: .addToCanvas(uuid: uuid)),
            .init(id: .goToObject, category: .object, title: "Go to Object", subtitle: nil, systemImage: "scope", shortcut: nil, role: .normal, availability: .enabled, intent: .goToObject(uuid: uuid)),
            .init(id: .copyCosmoLink, category: .object, title: "Copy Cosmo Link", subtitle: nil, systemImage: "link", shortcut: nil, role: .normal, availability: .enabled, intent: .copyCosmoLink(uuid: uuid)),
            .init(id: .deleteObject, category: .destructive, title: "Delete", subtitle: nil, systemImage: "trash", shortcut: nil, role: .destructive, availability: .enabled, intent: .deleteAtom(uuid: uuid))
        ]
    }

    private func swipeActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        guard case .swipe = context.selectionKind, let uuid = context.selectedAtomUUID else { return [] }
        let attachAvailability: CommandKActionAvailability = context.hasActiveContentDraft ? .enabled : .disabled(reason: "No active content draft")
        return [
            .init(id: .openSwipeStudy, category: .swipe, title: "Open Swipe Study", subtitle: nil, systemImage: "bolt.fill", shortcut: .commandS, role: .normal, availability: .enabled, intent: .openAtom(uuid: uuid)),
            .init(id: .analyzeSwipeHook, category: .swipe, title: "Analyze Hook", subtitle: nil, systemImage: "wand.and.stars", shortcut: nil, role: .normal, availability: .enabled, intent: .executeTool(name: "analyze_swipe_hook", arguments: ["uuid": uuid])),
            .init(id: .attachSwipeToCurrentDraft, category: .swipe, title: "Attach to Current Draft", subtitle: nil, systemImage: "paperclip", shortcut: nil, role: .normal, availability: attachAvailability, intent: .executeTool(name: "attach_swipe_to_current_draft", arguments: ["uuid": uuid])),
            .init(id: .useSwipeAsBlueprint, category: .swipe, title: "Use as Blueprint", subtitle: nil, systemImage: "rectangle.stack.badge.plus", shortcut: nil, role: .normal, availability: attachAvailability, intent: .executeTool(name: "use_swipe_as_blueprint", arguments: ["uuid": uuid])),
            .init(id: .createIdeaFromSwipe, category: .swipe, title: "Create Idea from Swipe", subtitle: nil, systemImage: "lightbulb.fill", shortcut: nil, role: .normal, availability: .enabled, intent: .executeTool(name: "create_idea_from_swipe", arguments: ["uuid": uuid])),
            .init(id: .findSimilarSwipes, category: .swipe, title: "Find Similar Swipes", subtitle: nil, systemImage: "point.3.connected.trianglepath.dotted", shortcut: nil, role: .normal, availability: .enabled, intent: .executeTool(name: "find_similar_swipes", arguments: ["uuid": uuid])),
            .init(id: .batchReprocessSwipeMedia, category: .swipe, title: "Reprocess Swipe Media", subtitle: nil, systemImage: "arrow.triangle.2.circlepath", shortcut: nil, role: .normal, availability: .enabled, intent: .executeTool(name: "reprocess_swipe_media", arguments: ["uuid": uuid]))
        ]
    }

    private func inquiryActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        guard let uuid = context.selectedAtomUUID else { return [] }
        let attachAvailability: CommandKActionAvailability = context.hasActiveInquirySession ? .enabled : .disabled(reason: "No active inquiry session")
        return [
            .init(id: .addToActiveInquiry, category: .inquiry, title: "Add to Active Inquiry", subtitle: nil, systemImage: "tray.and.arrow.down.fill", shortcut: nil, role: .normal, availability: attachAvailability, intent: .executeTool(name: "add_to_active_inquiry", arguments: ["uuid": uuid])),
            .init(id: .startInquiryOnSelection, category: .inquiry, title: "Start Inquiry on This", subtitle: nil, systemImage: "sparkle.magnifyingglass", shortcut: .commandI, role: .normal, availability: .enabled, intent: .startInquiry(anchorUUID: uuid, anchorType: context.subject.typeLabel))
        ]
    }

    private func commandCenterActions(for context: CommandKActionContext) -> [CommandKContextualAction] {
        guard let uuid = context.selectedAtomUUID else { return [] }
        var actions = [
            CommandKContextualAction(id: .createTaskFromSelection, category: .commandCenter, title: "Create Review Task", subtitle: nil, systemImage: "checkmark.circle.fill", shortcut: .commandT, role: .normal, availability: .enabled, intent: .commandCenter(.createReviewTask(sourceUUID: uuid)))
        ]

        if case .atom(.task) = context.selectionKind {
            actions.append(.init(id: .startFocusTask, category: .commandCenter, title: "Start Focus", subtitle: nil, systemImage: "play.circle.fill", shortcut: nil, role: .normal, availability: .enabled, intent: .commandCenter(.startFocus(taskUUID: uuid))))
            actions.append(.init(id: .markTaskDone, category: .commandCenter, title: "Mark Done", subtitle: nil, systemImage: "checkmark.seal.fill", shortcut: nil, role: .normal, availability: .enabled, intent: .commandCenter(.markDone(taskUUID: uuid))))
            actions.append(.init(id: .deferTask, category: .commandCenter, title: "Defer One Day", subtitle: nil, systemImage: "calendar.badge.clock", shortcut: nil, role: .normal, availability: .enabled, intent: .commandCenter(.defer(taskUUID: uuid, days: 1))))
            actions.append(.init(id: .scheduleTaskTomorrow, category: .commandCenter, title: "Schedule Tomorrow", subtitle: nil, systemImage: "calendar.badge.plus", shortcut: nil, role: .normal, availability: .enabled, intent: .commandCenter(.scheduleTomorrow(taskUUID: uuid))))
        }

        return actions
    }
}
```

- [ ] **Step 4: Run registry tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add UI/CommandK/Actions/CommandKActionRegistry.swift Tests/CosmoOSTests/CommandKActionRegistryTests.swift
git commit -m "feat: add command k action registry"
```

---

### Task 3: Add the Action Executor Boundary

**Files:**
- Create: `UI/CommandK/Actions/CommandKActionExecutor.swift`
- Test: `Tests/CosmoOSTests/CommandKActionExecutorTests.swift`
- Modify: `Core/CosmoNotifications.swift` only if a missing notification is needed.

- [ ] **Step 1: Write executor tests with a notification spy**

Add:

```swift
import XCTest
@testable import CosmoOS

final class CommandKActionExecutorTests: XCTestCase {
    @MainActor
    func testOpenAtomPostsExistingCommandKNotification() async throws {
        let recorder = NotificationRecorder(name: CosmoNotification.NodeGraph.openAtomFromCommandK)
        let executor = CommandKActionExecutor()

        try await executor.execute(.openAtom(uuid: "atom-1"))

        XCTAssertEqual(recorder.notifications.count, 1)
        XCTAssertEqual(recorder.notifications.first?.userInfo?["atomUUID"] as? String, "atom-1")
    }

    @MainActor
    func testStartInquiryPostsInquiryNotification() async throws {
        let recorder = NotificationRecorder(name: CosmoNotification.Inquiry.startInquiry)
        let executor = CommandKActionExecutor()

        try await executor.execute(.startInquiry(anchorUUID: "atom-1", anchorType: "Research"))

        XCTAssertEqual(recorder.notifications.count, 1)
        XCTAssertEqual(recorder.notifications.first?.userInfo?["anchorUUID"] as? String, "atom-1")
        XCTAssertEqual(recorder.notifications.first?.userInfo?["anchorType"] as? String, "Research")
    }
}

private final class NotificationRecorder {
    private(set) var notifications: [Notification] = []
    private var token: NSObjectProtocol?

    init(name: Notification.Name) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
            self?.notifications.append(notification)
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
```

- [ ] **Step 2: Run executor tests to verify failure**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionExecutorTests test
```

Expected: FAIL because `CommandKActionExecutor` does not exist.

- [ ] **Step 3: Implement notification and repository execution**

Create:

```swift
import AppKit
import Foundation

@MainActor
struct CommandKActionExecutor {
    func execute(_ intent: CommandKActionIntent) async throws {
        switch intent {
        case .openAtom(let uuid):
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.openAtomFromCommandK, object: nil, userInfo: ["atomUUID": uuid])
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
        case .openAsPane(let uuid):
            NotificationCenter.default.post(name: CosmoNotification.Navigation.openAsPane, object: nil, userInfo: ["atomUUID": uuid])
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
        case .addToCanvas(let uuid):
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.addToCanvas, object: nil, userInfo: ["atomUUID": uuid])
        case .goToObject(let uuid):
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.goToObjectFromCommandK, object: nil, userInfo: ["atomUUID": uuid])
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
        case .deleteAtom(let uuid):
            try await AtomRepository.shared.delete(uuid: uuid)
        case .copyCosmoLink(let uuid):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("cosmo://atom/\(uuid)", forType: .string)
        case .executeTool(let name, let arguments):
            _ = try await AgentToolExecutor.shared.execute(toolName: name, arguments: arguments)
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        case .postNotification(let name, let userInfo):
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        case .startInquiry(let anchorUUID, let anchorType):
            NotificationCenter.default.post(name: CosmoNotification.Inquiry.startInquiry, object: nil, userInfo: ["anchorUUID": anchorUUID, "anchorType": anchorType])
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.hideCommandK, object: nil)
        case .commandCenter(let intent):
            try await executeCommandCenter(intent)
        case .userCommand:
            break
        case .recipe:
            break
        }
    }

    private func executeCommandCenter(_ intent: CommandKCommandCenterIntent) async throws {
        switch intent {
        case .createReviewTask(let sourceUUID):
            _ = try await AgentToolExecutor.shared.execute(toolName: "create_review_task", arguments: ["sourceUUID": sourceUUID])
        case .startFocus(let taskUUID):
            NotificationCenter.default.post(name: CosmoNotification.Navigation.enterFocusMode, object: nil, userInfo: ["atomUUID": taskUUID])
        case .markDone(let taskUUID):
            _ = try await AgentToolExecutor.shared.execute(toolName: "complete_task", arguments: ["uuid": taskUUID])
        case .defer(let taskUUID, let days):
            _ = try await AgentToolExecutor.shared.execute(toolName: "defer_task", arguments: ["uuid": taskUUID, "days": "\(days)"])
        case .scheduleTomorrow(let taskUUID):
            _ = try await AgentToolExecutor.shared.execute(toolName: "schedule_task", arguments: ["uuid": taskUUID, "date": "tomorrow"])
        }
    }
}
```

- [ ] **Step 4: Run executor tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionExecutorTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add UI/CommandK/Actions/CommandKActionExecutor.swift Tests/CosmoOSTests/CommandKActionExecutorTests.swift Core/CosmoNotifications.swift
git commit -m "feat: execute command k contextual actions"
```

---

### Task 4: Render the Searchable Action Panel

**Files:**
- Create: `UI/CommandK/Actions/CommandKActionPanel.swift`
- Create: `UI/CommandK/Actions/CommandKActionPanelRow.swift`
- Modify: `UI/CommandK/CortexActionsMenu.swift`
- Modify: `UI/CommandK/CortexActionBar.swift`
- Modify: `UI/CommandK/CortexMasterDetailView.swift`
- Modify: `UI/CommandK/CommandKView.swift`

- [ ] **Step 1: Add action panel state**

Add to the view model or shell owner:

```swift
@State private var isActionPanelPresented = false
@State private var actionSearchQuery = ""
```

Use view-local state in `CommandKView` if the panel is purely presentational. Use `CommandKViewModel` only if tests need to assert panel state.

- [ ] **Step 2: Build `CommandKActionPanelRow`**

Create a row that uses `Button`, not `onTapGesture`, and shows disabled reasons:

```swift
import SwiftUI

struct CommandKActionPanelRow: View {
    let action: CommandKContextualAction
    let isSelected: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: DS.space12) {
                Image(systemName: action.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(iconStyle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(DS.body)
                        .foregroundStyle(action.availability.isEnabled ? DS.text : DS.textMuted)
                        .lineLimit(1)

                    if let subtitle = action.subtitle ?? disabledReason {
                        Text(subtitle)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DS.space12)

                if let shortcut = action.shortcut {
                    Text(shortcutLabel(shortcut))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.inkFaded)
                }
            }
            .padding(.horizontal, DS.space12)
            .frame(height: 48)
            .background(rowBackground)
            .clipShape(.rect(cornerRadius: DS.radiusSmall))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.availability.isEnabled)
        .accessibilityElement(children: .combine)
    }

    private var iconStyle: Color {
        action.role == .destructive ? DS.error : DS.accent
    }

    private var disabledReason: String? {
        if case .disabled(let reason) = action.availability { return reason }
        return nil
    }

    private var rowBackground: some ShapeStyle {
        isSelected ? DS.accentSoft : DS.surface.opacity(0)
    }

    private func shortcutLabel(_ shortcut: CommandKActionShortcut) -> String {
        switch shortcut {
        case .returnKey: return "↵"
        case .commandK: return "⌘K"
        case .commandS: return "⌘S"
        case .commandI: return "⌘I"
        case .commandT: return "⌘T"
        case .shiftCommandP: return "⇧⌘P"
        }
    }
}
```

- [ ] **Step 3: Build `CommandKActionPanel`**

Create a popover-like glass section that accepts grouped actions and filters by query:

```swift
import SwiftUI

struct CommandKActionPanel: View {
    let title: String
    let groups: [(category: CommandKActionCategory, actions: [CommandKContextualAction])]
    let execute: (CommandKContextualAction) -> Void

    @Binding var searchQuery: String
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            actionSearchField

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.space10) {
                        ForEach(filteredGroups, id: \.category) { group in
                            AtelierOrnamentalSectionLabel(group.category.rawValue.uppercased())
                            ForEach(group.actions) { action in
                                CommandKActionPanelRow(
                                    action: action,
                                    isSelected: flattenedActions[safe: selectedIndex]?.id == action.id,
                                    perform: { execute(action) }
                                )
                                .id(action.id.rawValue)
                            }
                        }
                    }
                    .padding(DS.space16)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    if let id = flattenedActions[safe: newIndex]?.id.rawValue {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 520, height: 520)
        .cortexGlassPanel()
        .accessibilityLabel(title)
    }

    private var actionSearchField: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.textMuted)
            TextField("Search actions...", text: $searchQuery)
                .textFieldStyle(.plain)
        }
        .padding(DS.space16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.sepiaBorder).frame(height: 0.5)
        }
    }

    private var filteredGroups: [(category: CommandKActionCategory, actions: [CommandKContextualAction])] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let actions = group.actions.filter {
                $0.title.lowercased().contains(query) ||
                ($0.subtitle?.lowercased().contains(query) ?? false) ||
                $0.category.rawValue.lowercased().contains(query)
            }
            return actions.isEmpty ? nil : (group.category, actions)
        }
    }

    private var flattenedActions: [CommandKContextualAction] {
        filteredGroups.flatMap(\.actions)
    }
}
```

If `Collection[safe:]` does not exist, add a local extension in the same file:

```swift
private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

- [ ] **Step 4: Wire `CortexActionBar` to registry primary action**

Change `CortexActionBar` inputs from only `selectedAtomUUID` to:

```swift
let primaryAction: CommandKContextualAction?
let actions: [CommandKContextualAction]
let onOpen: () -> Void
let onShowActions: () -> Void
```

The primary button label should be `primaryAction?.title ?? "Open"`. Disabled text uses `primaryAction?.availability`.

- [ ] **Step 5: Replace fixed `CortexActionsMenu` content**

Keep the old menu actions as executor-backed entries. `CortexActionsMenu` becomes a thin button:

```swift
struct CortexActionsMenu: View {
    let isEnabled: Bool
    let onShowActions: () -> Void

    var body: some View {
        Button(action: onShowActions) {
            HStack(spacing: DS.space6) {
                Text("Actions").font(DS.caption)
                CortexKeycap(symbol: "command")
                CortexKeycap(symbol: "K", isLetter: true)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Show actions")
    }
}
```

- [ ] **Step 6: Make `⌘K` inside open Command K show actions**

In `CommandKView.body` key handling, preserve the global open behavior, but when `isCommandKVisible` and the panel is focused, route `⌘K` to `isActionPanelPresented = true`.

- [ ] **Step 7: Manual visual check**

Run the app, open Command K, select a recent atom, press `⌘K`. Expected: searchable action panel appears, grouped actions render, disabled actions show a reason, Escape closes the panel before closing Command K.

- [ ] **Step 8: Commit**

```bash
git add UI/CommandK/Actions/CommandKActionPanel.swift UI/CommandK/Actions/CommandKActionPanelRow.swift UI/CommandK/CortexActionsMenu.swift UI/CommandK/CortexActionBar.swift UI/CommandK/CortexMasterDetailView.swift UI/CommandK/CommandKView.swift
git commit -m "feat: add command k action panel"
```

---

### Task 5: Add Command K Inline Forms

**Files:**
- Create: `UI/CommandK/Forms/CommandKFormModel.swift`
- Create: `UI/CommandK/Forms/CommandKInlineFormView.swift`
- Modify: `UI/CommandK/CommandKSearchPipeline.swift`
- Modify: `UI/CommandK/CommandKViewModel.swift`
- Modify: `UI/CommandK/CortexMasterDetailView.swift`
- Test: `Tests/CosmoOSTests/CommandKFormModelTests.swift`

- [ ] **Step 1: Write form model tests**

Add:

```swift
import XCTest
@testable import CosmoOS

final class CommandKFormModelTests: XCTestCase {
    func testCaptureSwipeFormRequiresURL() {
        var form = CommandKInlineFormModel(kind: .captureSwipe)

        XCTAssertEqual(form.primaryTitle, "Capture")
        XCTAssertFalse(form.validation.isValid)
        XCTAssertEqual(form.validation.message, "Paste a swipe URL")

        form.setValue("https://www.instagram.com/reel/abc", for: .url)

        XCTAssertTrue(form.validation.isValid)
        XCTAssertEqual(form.resolvedIntent, .executeTool(name: "capture_swipe", arguments: ["url": "https://www.instagram.com/reel/abc"]))
    }

    func testCreateTaskFormBuildsCreateTaskIntent() {
        var form = CommandKInlineFormModel(kind: .createTask)
        form.setValue("Review military-base swipe", for: .title)
        form.setValue("tomorrow", for: .date)

        XCTAssertTrue(form.validation.isValid)
        XCTAssertEqual(
            form.resolvedIntent,
            .executeTool(name: "create_task", arguments: ["title": "Review military-base swipe", "date": "tomorrow"])
        )
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKFormModelTests test
```

Expected: FAIL because form model does not exist.

- [ ] **Step 3: Implement form model**

Create:

```swift
import Foundation

enum CommandKInlineFormKind: String, Codable, Equatable {
    case captureSwipe
    case createTask
    case createIdea
    case createInquiry
    case createQuicklink
    case createSnippet
    case createRecipe
}

enum CommandKFormFieldID: String, Codable, Hashable {
    case url
    case title
    case body
    case date
    case client
    case attachTo
    case template
}

struct CommandKFormValidation: Equatable {
    let isValid: Bool
    let message: String?
}

struct CommandKInlineFormModel: Equatable {
    let kind: CommandKInlineFormKind
    private(set) var values: [CommandKFormFieldID: String] = [:]

    var primaryTitle: String {
        switch kind {
        case .captureSwipe: return "Capture"
        case .createTask: return "Create Task"
        case .createIdea: return "Create Idea"
        case .createInquiry: return "Start Inquiry"
        case .createQuicklink: return "Save Quicklink"
        case .createSnippet: return "Save Snippet"
        case .createRecipe: return "Save Recipe"
        }
    }

    var validation: CommandKFormValidation {
        switch kind {
        case .captureSwipe:
            guard value(for: .url).hasPrefix("http") else {
                return .init(isValid: false, message: "Paste a swipe URL")
            }
            return .init(isValid: true, message: nil)
        case .createTask, .createIdea, .createInquiry, .createQuicklink, .createSnippet, .createRecipe:
            guard !value(for: .title).isEmpty else {
                return .init(isValid: false, message: "Add a title")
            }
            return .init(isValid: true, message: nil)
        }
    }

    var resolvedIntent: CommandKActionIntent? {
        guard validation.isValid else { return nil }
        switch kind {
        case .captureSwipe:
            return .executeTool(name: "capture_swipe", arguments: ["url": value(for: .url)])
        case .createTask:
            return .executeTool(name: "create_task", arguments: compact(["title": value(for: .title), "date": value(for: .date)]))
        case .createIdea:
            return .executeTool(name: "create_idea", arguments: compact(["title": value(for: .title), "body": value(for: .body)]))
        case .createInquiry:
            return .executeTool(name: "create_inquiry", arguments: compact(["title": value(for: .title), "body": value(for: .body)]))
        case .createQuicklink:
            return .userCommand(id: "quicklink-form")
        case .createSnippet:
            return .userCommand(id: "snippet-form")
        case .createRecipe:
            return .recipe(id: "recipe-form")
        }
    }

    mutating func setValue(_ value: String, for field: CommandKFormFieldID) {
        values[field] = value
    }

    func value(for field: CommandKFormFieldID) -> String {
        values[field]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func compact(_ dictionary: [String: String]) -> [String: String] {
        dictionary.filter { !$0.value.isEmpty }
    }
}
```

- [ ] **Step 4: Extend parser to return form commands**

In `CommandKSearchPipeline.swift`, add aliases:

```swift
private static func parseInlineForm(_ text: String) -> CommandKInlineFormKind? {
    switch normalizedAlias(text) {
    case "capture swipe", "new swipe", "swipe form":
        return .captureSwipe
    case "new task", "task form":
        return .createTask
    case "new idea", "idea form":
        return .createIdea
    case "new inquiry", "start inquiry":
        return .createInquiry
    case "new quicklink", "save quicklink":
        return .createQuicklink
    case "new snippet", "save snippet":
        return .createSnippet
    case "new recipe", "save recipe":
        return .createRecipe
    default:
        return nil
    }
}
```

Wire this before generic search so exact aliases open forms.

- [ ] **Step 5: Render inline form in the shell**

`CortexMasterDetailView` switches the detail pane to `CommandKInlineFormView` when `viewModel.activeInlineForm != nil`. The rail still shows action/result context so the user can escape back.

- [ ] **Step 6: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKFormModelTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/CommandK/Forms UI/CommandK/CommandKSearchPipeline.swift UI/CommandK/CommandKViewModel.swift UI/CommandK/CortexMasterDetailView.swift Tests/CosmoOSTests/CommandKFormModelTests.swift
git commit -m "feat: add command k inline forms"
```

---

### Task 6: Build the Capture Router

**Files:**
- Create: `UI/CommandK/Capture/CommandKCapturePreview.swift`
- Create: `UI/CommandK/Capture/CommandKCaptureRouter.swift`
- Modify: `UI/CommandK/CommandKSearchPipeline.swift`
- Modify: `UI/CommandK/CommandKViewModel.swift`
- Test: `Tests/CosmoOSTests/CommandKCaptureRouterTests.swift`

- [ ] **Step 1: Write capture router tests**

Add:

```swift
import XCTest
@testable import CosmoOS

final class CommandKCaptureRouterTests: XCTestCase {
    func testInstagramReelURLResolvesToSwipeCapturePreview() {
        let preview = CommandKCaptureRouter().preview(for: "https://www.instagram.com/reel/ABC123/")

        XCTAssertEqual(preview?.kind, .swipe)
        XCTAssertEqual(preview?.source, .instagram)
        XCTAssertEqual(preview?.primaryAction.title, "Capture Swipe")
        XCTAssertEqual(preview?.primaryAction.intent, .executeTool(name: "capture_swipe", arguments: ["url": "https://www.instagram.com/reel/ABC123/"]))
    }

    func testPlainTextResolvesToIdeaOrTaskSuggestions() {
        let previews = CommandKCaptureRouter().suggestions(for: "Review hooks tomorrow")

        XCTAssertTrue(previews.contains { $0.kind == .task })
        XCTAssertTrue(previews.contains { $0.kind == .idea })
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKCaptureRouterTests test
```

Expected: FAIL because capture router types do not exist.

- [ ] **Step 3: Implement preview types**

Create:

```swift
import Foundation

enum CommandKCaptureKind: String, Codable, Equatable {
    case swipe
    case research
    case idea
    case task
    case content
    case inquiryExtract
}

enum CommandKCaptureSource: String, Codable, Equatable {
    case instagram
    case youtube
    case x
    case threads
    case website
    case text
}

struct CommandKCapturePreview: Identifiable, Equatable {
    let id: String
    let kind: CommandKCaptureKind
    let source: CommandKCaptureSource
    let title: String
    let subtitle: String
    let primaryAction: CommandKContextualAction
}
```

- [ ] **Step 4: Implement router**

Create:

```swift
import Foundation

struct CommandKCaptureRouter {
    private let classifier = SwipeURLClassifier()

    func preview(for input: String) -> CommandKCapturePreview? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard classifier.isURL(trimmed) else { return nil }
        let classification = classifier.classify(trimmed)
        let source = source(for: classification.sourceType)
        let kind: CommandKCaptureKind = isSwipeSource(classification.sourceType) ? .swipe : .research
        let title = kind == .swipe ? "Capture Swipe" : "Capture Research"
        let tool = kind == .swipe ? "capture_swipe" : "capture_research"

        return CommandKCapturePreview(
            id: "\(kind.rawValue)-\(trimmed)",
            kind: kind,
            source: source,
            title: title,
            subtitle: trimmed,
            primaryAction: CommandKContextualAction(
                id: kind == .swipe ? .runMemoryClip : .runQuicklink,
                category: .capture,
                title: title,
                subtitle: trimmed,
                systemImage: kind == .swipe ? "bolt.fill" : "doc.text.magnifyingglass",
                shortcut: .returnKey,
                role: .normal,
                availability: .enabled,
                intent: .executeTool(name: tool, arguments: ["url": trimmed])
            )
        )
    }

    func suggestions(for input: String) -> [CommandKCapturePreview] {
        if let preview = preview(for: input) { return [preview] }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [
            textPreview(kind: .task, title: "Create Task", tool: "create_task", input: trimmed),
            textPreview(kind: .idea, title: "Create Idea", tool: "create_idea", input: trimmed),
            textPreview(kind: .inquiryExtract, title: "Add Inquiry Extract", tool: "add_inquiry_extract", input: trimmed)
        ]
    }

    private func textPreview(kind: CommandKCaptureKind, title: String, tool: String, input: String) -> CommandKCapturePreview {
        CommandKCapturePreview(
            id: "\(kind.rawValue)-\(input)",
            kind: kind,
            source: .text,
            title: title,
            subtitle: input,
            primaryAction: CommandKContextualAction(
                id: .runMemoryClip,
                category: .capture,
                title: title,
                subtitle: input,
                systemImage: "text.badge.plus",
                shortcut: .returnKey,
                role: .normal,
                availability: .enabled,
                intent: .executeTool(name: tool, arguments: ["title": input])
            )
        )
    }

    private func isSwipeSource(_ sourceType: SwipeURLClassifier.SourceType) -> Bool {
        switch sourceType {
        case .instagramReel, .instagramPost, .instagramCarousel, .youtube, .youtubeShort, .xPost, .twitter, .threads:
            return true
        default:
            return false
        }
    }

    private func source(for sourceType: SwipeURLClassifier.SourceType) -> CommandKCaptureSource {
        switch sourceType {
        case .instagramReel, .instagramPost, .instagramCarousel:
            return .instagram
        case .youtube, .youtubeShort:
            return .youtube
        case .xPost, .twitter:
            return .x
        case .threads:
            return .threads
        case .website:
            return .website
        default:
            return .text
        }
    }
}
```

- [ ] **Step 5: Feed capture previews into Command K**

When `CommandKActionParser.parse` returns nil and query is non-empty, call `CommandKCaptureRouter().suggestions(for: query)` and show those as first-class command rows above search results.

- [ ] **Step 6: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKCaptureRouterTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/CommandK/Capture UI/CommandK/CommandKSearchPipeline.swift UI/CommandK/CommandKViewModel.swift Tests/CosmoOSTests/CommandKCaptureRouterTests.swift
git commit -m "feat: route command k capture previews"
```

---

### Task 7: Deepen Swipe Actions and Preview Behavior

**Files:**
- Modify: `UI/CommandK/CortexDetailPane.swift`
- Modify: `UI/CommandK/SwipeGalleryCardView.swift` only if preview media helpers are duplicated there.
- Modify: `UI/CommandK/Actions/CommandKActionRegistry.swift`
- Modify: `UI/CommandK/Actions/CommandKActionExecutor.swift`
- Test: `Tests/CosmoOSTests/SwipeProcessingServiceTests.swift`
- Test: `Tests/CosmoOSTests/CommandKActionRegistryTests.swift`

- [ ] **Step 1: Add tests for swipe action availability**

Append to `CommandKActionRegistryTests`:

```swift
func testAttachSwipeIsDisabledWithoutActiveDraft() {
    let subject = CortexDetailSubject.swipe(
        SwipeGalleryItem(atomUUID: "swipe-1", title: "Swipe", hookText: nil, hookScore: nil, platform: "instagram", thumbnailUrl: nil, author: nil)
    )
    let context = CommandKActionContext(query: "", subject: subject, hydratedAtom: nil, mode: .compact, activeInquirySessionUUID: nil, activeContentDraftUUID: nil)

    let action = CommandKActionRegistry().actions(for: context).first { $0.id == .attachSwipeToCurrentDraft }

    XCTAssertEqual(action?.availability, .disabled(reason: "No active content draft"))
}
```

- [ ] **Step 2: Make preview media fit type**

In `CortexDetailPane`, enforce these layout rules:

- Reel/video: portrait container, playable video surface when `extractedMediaURL` or local cached video exists.
- Carousel: square container with full image fitting, not cropping, plus previous/next controls and `1 / N`.
- Website/image: aspect-fit in a bordered preview frame.
- Missing media: skeleton with source metadata and a `Reprocess Swipe Media` action.

- [ ] **Step 3: Add carousel navigation state**

Use stable local state:

```swift
@State private var carouselIndexBySubjectID: [String: Int] = [:]
```

The selected index key should be the selected atom UUID or media ID. Clamp index when media count changes.

- [ ] **Step 4: Wire swipe actions to existing services**

Executor tool mapping:

```swift
case .executeTool(let name, let arguments):
    switch name {
    case "reprocess_swipe_media":
        if let uuid = arguments["uuid"] {
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.batchSwipeAnalysisTriggered, object: nil, userInfo: ["atomUUID": uuid])
        }
    default:
        _ = try await AgentToolExecutor.shared.execute(toolName: name, arguments: arguments)
    }
```

- [ ] **Step 5: Manual visual check**

Open Command K over a reel, a carousel, and a non-media research item. Expected: video reads as video, carousel is square with complete thumbnail visible, carousel controls work, action panel exposes swipe actions.

- [ ] **Step 6: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/SwipeProcessingServiceTests test
```

Expected: PASS or existing unrelated failures recorded.

- [ ] **Step 7: Commit**

```bash
git add UI/CommandK/CortexDetailPane.swift UI/CommandK/SwipeGalleryCardView.swift UI/CommandK/Actions/CommandKActionRegistry.swift UI/CommandK/Actions/CommandKActionExecutor.swift Tests/CosmoOSTests/CommandKActionRegistryTests.swift Tests/CosmoOSTests/SwipeProcessingServiceTests.swift
git commit -m "feat: add rich swipe command actions"
```

---

### Task 8: Add Inquiry Command Surface

**Files:**
- Modify: `UI/CommandK/Actions/CommandKActionRegistry.swift`
- Modify: `UI/CommandK/Actions/CommandKActionExecutor.swift`
- Modify: `Core/CosmoNotifications.swift` only if active session state lacks a notification.
- Modify: `UI/FocusMode/Inquiry/InquiryWorkspaceViewModel.swift` only if a notification listener is missing.
- Test: `Tests/CosmoOSTests/CommandKActionRegistryTests.swift`
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Add inquiry action tests**

Append:

```swift
func testInquiryActionsIncludeRefreshAndCrystallizeWhenInquiryIsActive() {
    let context = CommandKActionContext(
        query: "",
        subject: .empty,
        hydratedAtom: nil,
        mode: .compact,
        activeInquirySessionUUID: "session-1",
        activeContentDraftUUID: nil
    )

    let actions = CommandKActionRegistry().actions(for: context)
    let ids = actions.map(\.id)

    XCTAssertTrue(ids.contains(.refreshInquirySources))
    XCTAssertTrue(ids.contains(.crystallizeInquiry))
}
```

- [ ] **Step 2: Add active inquiry actions**

Registry should add these when `context.hasActiveInquirySession`:

```swift
.init(id: .refreshInquirySources, category: .inquiry, title: "Refresh Inquiry Sources", subtitle: nil, systemImage: "arrow.clockwise", shortcut: nil, role: .normal, availability: .enabled, intent: .postNotification(name: CosmoNotification.Inquiry.refreshSources, userInfo: [:])),
.init(id: .crystallizeInquiry, category: .inquiry, title: "Crystallize Inquiry", subtitle: nil, systemImage: "seal.fill", shortcut: nil, role: .normal, availability: .enabled, intent: .postNotification(name: CosmoNotification.Inquiry.crystallizeActive, userInfo: [:]))
```

- [ ] **Step 3: Add layout actions**

Add actions for Inquiry layout modes:

- `Inquiry: Research`
- `Inquiry: Read`
- `Inquiry: Write`
- `Inquiry: Map`
- `Inquiry: Review`

These post `CosmoNotification.Inquiry.layoutRequested` with the existing `LayoutPayload`.

- [ ] **Step 4: Add "Add selected to active inquiry" execution**

If an atom is selected and there is an active inquiry session, execute:

```swift
NotificationCenter.default.post(
    name: CosmoNotification.Inquiry.addExtractToInquiry,
    object: nil,
    userInfo: ["extractUUID": uuid]
)
```

If the selected object is not an extract, use an AgentToolExecutor tool named `create_inquiry_extract_from_atom` and pass `atomUUID` plus active `sessionUUID`.

- [ ] **Step 5: Manual check**

Start an inquiry, open Command K, select a research source, press `⌘K`. Expected: add-to-inquiry, refresh sources, crystallize, and layout actions are present.

- [ ] **Step 6: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/InquiryPlacementEngineTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/CommandK/Actions/CommandKActionRegistry.swift UI/CommandK/Actions/CommandKActionExecutor.swift Core/CosmoNotifications.swift UI/FocusMode/Inquiry/InquiryWorkspaceViewModel.swift Tests/CosmoOSTests/CommandKActionRegistryTests.swift Tests/CosmoOSTests/InquiryPlacementEngineTests.swift
git commit -m "feat: expose inquiry actions in command k"
```

---

### Task 9: Add Command Center Task Actions

**Files:**
- Modify: `UI/CommandK/Actions/CommandKActionRegistry.swift`
- Modify: `UI/CommandK/Actions/CommandKActionExecutor.swift`
- Modify: `Canvas/CommandCenter/CommandCenterDashboardViewModel.swift` if task mutations are not available through tools.
- Modify: `Canvas/CommandCenter/CommandCenterTaskMenus.swift` if shared action definitions reduce duplication.
- Test: `Tests/CosmoOSTests/CommandCenterComposerTests.swift`
- Test: `Tests/CosmoOSTests/CommandKActionRegistryTests.swift`

- [ ] **Step 1: Add task action tests**

Append:

```swift
func testTaskSelectionGetsTaskOperations() {
    let subject = CortexDetailSubject.recent(
        RecentDisplayItem(id: "task-1", title: "Write reel", type: .task, entityId: 1, relativeDate: "today", thumbnailURL: nil, preview: nil)
    )
    let context = CommandKActionContext(query: "", subject: subject, hydratedAtom: nil, mode: .compact, activeInquirySessionUUID: nil, activeContentDraftUUID: nil)

    let ids = CommandKActionRegistry().actions(for: context).map(\.id)

    XCTAssertTrue(ids.contains(.startFocusTask))
    XCTAssertTrue(ids.contains(.markTaskDone))
    XCTAssertTrue(ids.contains(.deferTask))
    XCTAssertTrue(ids.contains(.scheduleTaskTomorrow))
}
```

- [ ] **Step 2: Wire task mutations**

Prefer existing task mutation services. If no public method exists, add thin methods to the Command Center view model or repository layer:

```swift
@MainActor
func completeTask(uuid: String) async throws

@MainActor
func scheduleTask(uuid: String, date: Date) async throws

@MainActor
func deferTask(uuid: String, byDays days: Int) async throws
```

These methods must update `TaskMetadata.completedAt`, `TaskMetadata.focusDate` or scheduling fields consistently with `CommandCenterScheduleUtilities`.

- [ ] **Step 3: Add natural language command aliases**

In `CommandKSearchPipeline`, recognize:

- `today`
- `command center`
- `new task`
- `task: <title>`
- `focus <task title>`
- `defer <task title>`

Existing `task:` behavior stays compatible.

- [ ] **Step 4: Manual check**

Open Command K on a task and verify actions. Execute `Schedule Tomorrow` and confirm Command Center updates.

- [ ] **Step 5: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandCenterComposerTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/CommandK/Actions/CommandKActionRegistry.swift UI/CommandK/Actions/CommandKActionExecutor.swift UI/CommandK/CommandKSearchPipeline.swift Canvas/CommandCenter/CommandCenterDashboardViewModel.swift Canvas/CommandCenter/CommandCenterTaskMenus.swift Tests/CosmoOSTests/CommandCenterComposerTests.swift Tests/CosmoOSTests/CommandKActionRegistryTests.swift
git commit -m "feat: add command center actions to command k"
```

---

### Task 10: Add Cosmo Quicklinks

**Files:**
- Create: `UI/CommandK/UserCommands/CommandKUserCommandModels.swift`
- Create: `UI/CommandK/UserCommands/CommandKUserCommandStore.swift`
- Create: `UI/CommandK/UserCommands/CommandKUserCommandSearchComposer.swift`
- Modify: `UI/CommandK/CommandKViewModel.swift`
- Modify: `UI/CommandK/CortexResultRail.swift`
- Test: `Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift`

- [ ] **Step 1: Write store tests**

Add:

```swift
import XCTest
@testable import CosmoOS

final class CommandKUserCommandStoreTests: XCTestCase {
    func testQuicklinksPersistAndSearchByAlias() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let store = CommandKUserCommandStore(fileURL: url)
        let quicklink = CommandKQuicklink(id: "today", alias: "today", title: "Today", route: .commandCenter, query: nil, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))

        try await store.saveQuicklink(quicklink)

        let results = try await store.searchQuicklinks("tod")
        XCTAssertEqual(results.map(\.id), ["today"])
    }
}
```

- [ ] **Step 2: Implement models**

Add:

```swift
import Foundation

enum CommandKQuicklinkRoute: Codable, Equatable {
    case commandCenter
    case commandKDomain(String)
    case atom(String)
    case thinkspace(String)
    case savedSearch(String)
}

struct CommandKQuicklink: Identifiable, Codable, Equatable {
    let id: String
    var alias: String
    var title: String
    var route: CommandKQuicklinkRoute
    var query: String?
    var createdAt: Date
    var updatedAt: Date
}
```

- [ ] **Step 3: Implement file-backed store**

Use an actor with atomic read/write:

```swift
import Foundation

actor CommandKUserCommandStore {
    private let fileURL: URL
    private var state: CommandKUserCommandState

    init(fileURL: URL = CommandKUserCommandStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.state = (try? Self.load(from: fileURL)) ?? CommandKUserCommandState()
    }

    func saveQuicklink(_ quicklink: CommandKQuicklink) throws {
        state.quicklinks.removeAll { $0.id == quicklink.id }
        state.quicklinks.append(quicklink)
        try persist()
    }

    func searchQuicklinks(_ query: String) throws -> [CommandKQuicklink] {
        let normalized = query.lowercased()
        return state.quicklinks.filter {
            normalized.isEmpty ||
            $0.alias.lowercased().contains(normalized) ||
            $0.title.lowercased().contains(normalized)
        }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> CommandKUserCommandState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CommandKUserCommandState.self, from: data)
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CosmoOS", isDirectory: true)
            .appendingPathComponent("CommandKUserCommands.json")
    }
}

struct CommandKUserCommandState: Codable, Equatable {
    var quicklinks: [CommandKQuicklink] = []
    var clips: [CommandKMemoryClip] = []
    var snippets: [CommandKSnippet] = []
    var recipes: [CommandKActionRecipe] = []
}
```

- [ ] **Step 4: Seed built-in quicklinks**

On first load, seed:

- `today` -> Command Center
- `swipes` -> Swipe File domain
- `ideas` -> Ideas domain
- `library` -> Library domain
- `database` -> Database domain
- `inquiries` -> Inquiry domain

- [ ] **Step 5: Render quicklink rows**

`CommandKUserCommandSearchComposer` returns rows for query matches. Put them above generic search results when the alias match is strong.

- [ ] **Step 6: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKUserCommandStoreTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/CommandK/UserCommands Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift UI/CommandK/CommandKViewModel.swift UI/CommandK/CortexResultRail.swift
git commit -m "feat: add command k quicklinks"
```

---

### Task 11: Add Memory Clips

**Files:**
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandModels.swift`
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandStore.swift`
- Modify: `UI/CommandK/Actions/CommandKActionRegistry.swift`
- Modify: `UI/CommandK/Actions/CommandKActionExecutor.swift`
- Test: `Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift`

- [ ] **Step 1: Add memory clip model tests**

Append:

```swift
func testMemoryClipsKeepMostRecentFirst() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let store = CommandKUserCommandStore(fileURL: url)
    try await store.saveClip(CommandKMemoryClip(id: "old", title: "Old", text: "old", sourceAtomUUID: nil, createdAt: Date(timeIntervalSince1970: 1), lastUsedAt: Date(timeIntervalSince1970: 1)))
    try await store.saveClip(CommandKMemoryClip(id: "new", title: "New", text: "new", sourceAtomUUID: nil, createdAt: Date(timeIntervalSince1970: 2), lastUsedAt: Date(timeIntervalSince1970: 2)))

    let clips = try await store.recentClips(limit: 2)

    XCTAssertEqual(clips.map(\.id), ["new", "old"])
}
```

- [ ] **Step 2: Add clip model**

```swift
struct CommandKMemoryClip: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var text: String
    var sourceAtomUUID: String?
    var createdAt: Date
    var lastUsedAt: Date
}
```

- [ ] **Step 3: Add clip store methods**

```swift
func saveClip(_ clip: CommandKMemoryClip) throws {
    state.clips.removeAll { $0.id == clip.id }
    state.clips.append(clip)
    try persist()
}

func recentClips(limit: Int) throws -> [CommandKMemoryClip] {
    Array(state.clips.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(limit))
}
```

- [ ] **Step 4: Add actions**

For selected atom:

- `Save as Memory Clip`
- `Copy Clip Text`
- `Create Task from Clip`
- `Create Idea from Clip`

For text query:

- `Save Query as Memory Clip`

- [ ] **Step 5: Execute clip copy**

Use `NSPasteboard.general` for copy. For create actions, call `AgentToolExecutor` with `create_task` or `create_idea`.

- [ ] **Step 6: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKUserCommandStoreTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/CommandK/UserCommands UI/CommandK/Actions Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift
git commit -m "feat: add command k memory clips"
```

---

### Task 12: Add Snippets and Templates

**Files:**
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandModels.swift`
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandStore.swift`
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandSearchComposer.swift`
- Modify: `UI/CommandK/Forms/CommandKInlineFormView.swift`
- Test: `Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift`

- [ ] **Step 1: Add snippet model test**

Append:

```swift
func testSnippetExpansionReplacesVariables() {
    let snippet = CommandKSnippet(
        id: "reel",
        alias: "reel brief",
        title: "Reel Brief",
        body: "Hook: {{hook}}\nClient: {{client}}",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )

    let expanded = snippet.expanded(with: ["hook": "Buy near bases", "client": "Acme"])

    XCTAssertEqual(expanded, "Hook: Buy near bases\nClient: Acme")
}
```

- [ ] **Step 2: Add snippet model**

```swift
struct CommandKSnippet: Identifiable, Codable, Equatable {
    let id: String
    var alias: String
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    func expanded(with values: [String: String]) -> String {
        values.reduce(body) { result, pair in
            result.replacingOccurrences(of: "{{\(pair.key)}}", with: pair.value)
        }
    }
}
```

- [ ] **Step 3: Seed templates**

Seed built-ins:

- Reel brief
- Carousel outline
- Inquiry source note
- Client content task
- Research distillation

- [ ] **Step 4: Render snippets in search**

When query matches alias/title, show snippet row with actions:

- Copy
- Create Idea
- Create Content Draft
- Create Task

- [ ] **Step 5: Add snippet form**

The inline form captures `alias`, `title`, and `body`. Save through `CommandKUserCommandStore`.

- [ ] **Step 6: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKUserCommandStoreTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/CommandK/UserCommands UI/CommandK/Forms Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift
git commit -m "feat: add command k snippets"
```

---

### Task 13: Add Action Frecency, Pinning, and Native Commands

**Files:**
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandModels.swift`
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandStore.swift`
- Modify: `UI/CommandK/Actions/CommandKActionRegistry.swift`
- Modify: `Core/CosmoApp.swift`
- Test: `Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift`

- [ ] **Step 1: Add action usage model**

```swift
struct CommandKActionUsage: Identifiable, Codable, Equatable {
    let id: String
    var actionID: String
    var useCount: Int
    var lastUsedAt: Date
    var isPinned: Bool
}
```

- [ ] **Step 2: Add tests for ranking**

```swift
func testPinnedActionsSortBeforeRecentActions() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let store = CommandKUserCommandStore(fileURL: url)
    try await store.recordActionUse(actionID: "copy", date: Date(timeIntervalSince1970: 3), pinned: false)
    try await store.recordActionUse(actionID: "open", date: Date(timeIntervalSince1970: 1), pinned: true)

    let usage = try await store.actionUsageRanked()

    XCTAssertEqual(usage.map(\.actionID), ["open", "copy"])
}
```

- [ ] **Step 3: Add pin action to action panel**

`⇧⌘P` toggles pin for the selected action. Pinned actions appear at the top of the Action Panel under `Pinned`.

- [ ] **Step 4: Add native macOS Commands**

In `Core/CosmoApp.swift`, expose:

- Command K Action Panel
- Capture Swipe
- New Task
- Start Inquiry
- Refresh Inquiry Sources
- Crystallize Inquiry

Use existing shortcuts only where they do not conflict.

- [ ] **Step 5: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKUserCommandStoreTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/CommandK/UserCommands UI/CommandK/Actions Core/CosmoApp.swift Tests/CosmoOSTests/CommandKUserCommandStoreTests.swift
git commit -m "feat: rank and pin command k actions"
```

---

### Task 14: Add Action Recipes

**Files:**
- Create: `UI/CommandK/Recipes/CommandKRecipeRunner.swift`
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandModels.swift`
- Modify: `UI/CommandK/UserCommands/CommandKUserCommandStore.swift`
- Modify: `UI/CommandK/Actions/CommandKActionExecutor.swift`
- Test: `Tests/CosmoOSTests/CommandKRecipeRunnerTests.swift`

- [ ] **Step 1: Write recipe tests**

Add:

```swift
import XCTest
@testable import CosmoOS

final class CommandKRecipeRunnerTests: XCTestCase {
    @MainActor
    func testRecipeStopsWhenRequiredArgumentIsMissing() async {
        let recipe = CommandKActionRecipe(
            id: "capture-review",
            alias: "capture review",
            title: "Capture and Review",
            steps: [
                .init(intent: .executeTool(name: "capture_swipe", arguments: ["url": "{{url}}"]), continueOnFailure: false),
                .init(intent: .executeTool(name: "create_task", arguments: ["title": "Review {{url}}"]), continueOnFailure: false)
            ],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        let result = await CommandKRecipeRunner(executor: CommandKActionExecutor()).validate(recipe, arguments: [:])

        XCTAssertEqual(result, .missingArgument("url"))
    }
}
```

- [ ] **Step 2: Add recipe models**

```swift
struct CommandKActionRecipe: Identifiable, Codable, Equatable {
    let id: String
    var alias: String
    var title: String
    var steps: [CommandKActionRecipeStep]
    var createdAt: Date
    var updatedAt: Date
}

struct CommandKActionRecipeStep: Codable, Equatable {
    var intent: CommandKActionIntent
    var continueOnFailure: Bool
}

enum CommandKRecipeValidationResult: Equatable {
    case valid
    case missingArgument(String)
}
```

If `CommandKActionIntent` cannot become Codable without creating brittle notification serialization, define a recipe-specific Codable intent:

```swift
enum CommandKRecipeIntent: Codable, Equatable {
    case tool(name: String, arguments: [String: String])
    case notification(name: String, userInfo: [String: String])
}
```

- [ ] **Step 3: Implement runner**

```swift
@MainActor
struct CommandKRecipeRunner {
    let executor: CommandKActionExecutor

    func validate(_ recipe: CommandKActionRecipe, arguments: [String: String]) async -> CommandKRecipeValidationResult {
        for step in recipe.steps {
            for value in step.intent.argumentValues {
                if let key = Self.placeholderKey(in: value), arguments[key] == nil {
                    return .missingArgument(key)
                }
            }
        }
        return .valid
    }

    func run(_ recipe: CommandKActionRecipe, arguments: [String: String]) async throws {
        guard await validate(recipe, arguments: arguments) == .valid else { return }
        for step in recipe.steps {
            do {
                try await executor.execute(step.intent.resolved(with: arguments))
            } catch {
                if !step.continueOnFailure { throw error }
            }
        }
    }

    private static func placeholderKey(in value: String) -> String? {
        guard value.hasPrefix("{{"), value.hasSuffix("}}") else { return nil }
        return String(value.dropFirst(2).dropLast(2))
    }
}
```

Add helper extensions for argument extraction and resolution.

- [ ] **Step 4: Seed starter recipes**

Seed:

- Capture swipe -> analyze -> create review task
- Add selected source -> active inquiry -> refresh sources
- Create idea from swipe -> attach swipe -> create task

- [ ] **Step 5: Run tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKRecipeRunnerTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/CommandK/Recipes UI/CommandK/UserCommands UI/CommandK/Actions Tests/CosmoOSTests/CommandKRecipeRunnerTests.swift
git commit -m "feat: add command k action recipes"
```

---

### Task 15: Final Polish, Accessibility, and Verification

**Files:**
- Modify: `UI/CommandK/Actions/CommandKActionPanel.swift`
- Modify: `UI/CommandK/Actions/CommandKActionPanelRow.swift`
- Modify: `UI/CommandK/Forms/CommandKInlineFormView.swift`
- Modify: `UI/CommandK/CortexActionBar.swift`
- Modify: `UI/CommandK/CortexDetailPane.swift`
- Modify: `UI/CommandK/CortexResultRail.swift`

- [ ] **Step 1: Accessibility pass**

Verify:

- Every action row is a `Button`.
- Icon-only controls have `accessibilityLabel`.
- Rows use `accessibilityElement(children: .combine)`.
- Hit targets are at least 44pt tall.
- Disabled action reasons are visible and conveyed in accessibility labels.

- [ ] **Step 2: Keyboard pass**

Verify:

- Up/down navigates rail.
- `Enter` runs primary action.
- `⌘K` opens Action Panel while Command K is already open.
- Escape closes Action Panel first, then Command K.
- Form fields can be tabbed through.
- `⇧⌘P` pins the selected action after Task 13.

- [ ] **Step 3: Visual pass**

Verify:

- No nested cards inside cards.
- Action panel uses glass/vellum chrome and sepia hairlines.
- Rail remains dense and readable.
- Swipe video/carousel preview stays stable when changing slides.
- Long action labels truncate cleanly.
- Disabled rows are readable but quiet.

- [ ] **Step 4: Run targeted tests**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionRegistryTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKActionExecutorTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKFormModelTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKCaptureRouterTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKUserCommandStoreTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandKRecipeRunnerTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/CommandCenterComposerTests test
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOSTests -configuration Debug -only-testing:CosmoOSTests/InquiryPlacementEngineTests test
```

Expected: PASS, except known unrelated target-level failures recorded with exact output.

- [ ] **Step 5: Run full build**

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: PASS, or known unrelated `CosmoVoiceDaemon` / `MLXEmbedders.ModelContainer` blocker recorded.

- [ ] **Step 6: Manual QA script**

Run through:

1. Open Command K.
2. Select a recent research item.
3. Press `⌘K`.
4. Run `Copy Cosmo Link`.
5. Select a swipe.
6. Press `⌘K`.
7. Run `Open Swipe Study`.
8. Search for `capture swipe`.
9. Paste an Instagram URL and execute.
10. Start an inquiry, then select a source and run `Add to Active Inquiry`.
11. Select a task and run `Schedule Tomorrow`.
12. Search `today` and open Command Center quicklink.
13. Run a snippet and copy it.
14. Run a starter recipe.

- [ ] **Step 7: Commit polish**

```bash
git add UI/CommandK Core Canvas Tests
git commit -m "polish: finish command k operating layer"
```

---

## Execution Strategy

Recommended execution is subagent-driven with review gates:

1. Foundation worker: Tasks 1-3.
2. UI worker: Task 4 and Task 15 visual polish.
3. Forms/capture worker: Tasks 5-6.
4. Domain actions worker: Tasks 7-9.
5. User command worker: Tasks 10-14.

Do not run overlapping workers on the same files at the same time unless write scopes are narrowed. In particular, `CommandKActionRegistry.swift`, `CommandKActionExecutor.swift`, `CommandKViewModel.swift`, and `CortexMasterDetailView.swift` are shared integration files.

## Self-Review

Spec coverage:

- Universal Object Action Panel: covered by Tasks 1-4 and Task 13.
- Command K Capture Router: covered by Tasks 5-6.
- Swipe-specific actions and richer preview: covered by Task 7.
- Command K Forms: covered by Task 5.
- Cosmo Quicklinks: covered by Task 10.
- Memory Clips: covered by Task 11.
- Snippets/Templates: covered by Task 12.
- Inquiry actions: covered by Task 8.
- Command Center actions: covered by Task 9.
- Action Recipes: covered by Task 14.
- Accessibility, keyboard, visual QA, and build verification: covered by Task 15.

Placeholder scan:

- The plan avoids deferred placeholders. Where code depends on existing unavailable app services, the task names the exact bridge method or notification to add.

Type consistency:

- `CommandKActionContext`, `CommandKContextualAction`, `CommandKActionIntent`, `CommandKActionRegistry`, `CommandKActionExecutor`, `CommandKInlineFormModel`, `CommandKCaptureRouter`, `CommandKUserCommandStore`, and `CommandKRecipeRunner` are introduced before later tasks depend on them.
