# Cosmo Inline Assistant and Diff Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Google Docs Gemini-style Cosmo assistant that works from a bottom composer across Cosmo surfaces, opens a right pane for conversational answers, and stages inline/canvas diffs with per-change accept and reject controls for edits.

**Architecture:** Add a universal inline assistant layer owned by `MainView`, with a focused `CosmoInlineAssistantStore` coordinating prompt submission, active surface snapshots, proposal state, and pane routing. Extend the existing `CosmoContextProvider` pattern with `CosmoEditableSurfaceProvider` so notes, content drafts, ideas, connections, and canvases publish stable editable snapshots and apply reviewed proposal operations. Route all model work through the existing `CosmoAgentService` and `AgentToolExecutor`, adding review-first tools that produce `CosmoAssistantProposal` objects instead of mutating app state directly.

**Tech Stack:** Swift 5.9/6, SwiftUI for macOS 26, existing `CosmoAgentService`, `AgentToolRegistry`, `AgentToolExecutor`, `PaneManager`, `EditorCommandBus`, `CosmoContextProvider`, XCTest, Xcode project generated from `project.yml` or updated with a file-add script.

---

## Product Rules

1. Option-A opens or focuses the bottom inline assistant composer.
2. The pane button on the bottom composer opens the assistant pane immediately.
3. If the prompt is a question or a conversational request, the assistant opens the pane and streams the answer there.
4. If the prompt is an edit/action request, the assistant keeps the main workspace in focus and stages reviewed proposal operations inline.
5. Every mutating operation is review-first. The model may propose edits, layout moves, structured field changes, or canvas organization, but it must not directly mutate app state.
6. Every proposal operation has independent accept and reject controls. Global accept all and reject all are available when there is more than one operation.
7. Proposal application verifies the source hash or source version before applying. If content changed since proposal creation, mark the operation conflicted and require regeneration.
8. The assistant uses the same model policy and context-window behavior as Command A/CosmoWindow.
9. CommandK remains the object/action launcher. This assistant becomes the "work with the active surface" AI layer.
10. The first shippable slice covers note, content draft, idea body/hooks, and thinkspace canvas operations. Connection/Research/Codex structured editing is added after the common machinery is working.

## Visual Layout

```text
Main / Focus / Canvas Surface
+--------------------------------------------------------------------+
|                                                                    |
|  active document, focus mode, codex, outline, hooks, or canvas      |
|                                                                    |
|      changed paragraph / block / canvas item                        |
|      +----------------------------------------------+  OK  X        |
|      | old text muted/struck, new text accent-tinted|               |
|      +----------------------------------------------+               |
|                                                                    |
|                 +--------------------------------------+            |
|                 | spark  Describe changes... pane send |            |
|                 +--------------------------------------+            |
+--------------------------------------------------------------------+

Conversational Answer Mode
+------------------------------------------+-------------------------+
| active workspace                         | Cosmo Assistant         |
|                                          | user prompt             |
|                                          | assistant response      |
|                                          | follow-up composer      |
+------------------------------------------+-------------------------+
```

## File Structure

- Create `UI/InlineAssistant/CosmoInlineAssistantModels.swift`
  - Proposal, operation, hunk, route, status, and source snapshot value types.
- Create `UI/InlineAssistant/CosmoEditableSurfaceProvider.swift`
  - Protocol for surfaces that can expose editable snapshots and apply/reject proposal operations.
- Create `UI/InlineAssistant/CosmoEditableSurfaceRegistry.swift`
  - Main-actor registry for the currently active editable surface.
- Create `UI/InlineAssistant/CosmoInlineAssistantStore.swift`
  - State coordinator for composer text, prompt submission, proposal state, pane routing, and callbacks from agent tools.
- Create `UI/InlineAssistant/CosmoInlineAssistantAgentBridge.swift`
  - Thin bridge into `CosmoAgentService` and `AgentToolExecutor` callbacks.
- Create `UI/InlineAssistant/CosmoInlineAssistantBar.swift`
  - Bottom floating composer UI.
- Create `UI/InlineAssistant/CosmoInlineAssistantPaneView.swift`
  - Side pane conversation UI for inline assistant sessions.
- Create `UI/InlineAssistant/CosmoInlineProposalOverlay.swift`
  - Shared inline proposal review UI for text and structured edits.
- Create `UI/InlineAssistant/CosmoInlineAssistantDiffEngine.swift`
  - Deterministic line/paragraph hunk construction for review cards and inline overlays.
- Create `UI/InlineAssistant/CosmoWorkspaceEditApplicator.swift`
  - Applies accepted proposal operations through `EditorCommandBus`, focus state models, or canvas services.
- Modify `Core/CosmoNotifications.swift`
  - Add notifications for opening/focusing inline assistant and assistant pane.
- Modify `Navigation/MainView.swift`
  - Own and render the bottom assistant overlay, register shortcut handling, and route pane open notifications.
- Modify `Navigation/PaneManager.swift`
  - Add `.inlineAssistant` pane content and activation helpers.
- Modify `Navigation/PaneContentView.swift`
  - Render `CosmoInlineAssistantPaneView`.
- Modify `Agent/Core/AgentToolRegistry.swift`
  - Add `propose_workspace_edit`, `propose_workspace_canvas_plan`, and `answer_in_assistant_pane` tool definitions for in-app assistant response mode.
- Modify `Agent/Core/AgentToolExecutor.swift`
  - Add callbacks and execution handlers for workspace proposals and pane answers.
- Modify `UI/CosmoWindow/CosmoContextProvider.swift`
  - Add editable surface metadata to context data without breaking existing providers.
- Modify `Editor/EditorCommandBus.swift`
  - Add reviewed edit notifications for anchored range replacement and full-field replacement.
- Modify `UI/FocusMode/Notes/NoteFocusModeView.swift`
  - Register a note editable surface provider and implement note body operations.
- Modify `UI/FocusMode/Content/ContentFocusModeView.swift`
  - Register a content editable surface provider and implement draft operations.
- Modify `UI/FocusMode/Ideas/IdeaFocusModeView.swift`
  - Register an idea editable surface provider for body and hooks.
- Modify `Canvas/CanvasView.swift`
  - Register a canvas editable surface provider and render canvas proposal previews.
- Test `Tests/CosmoOSTests/CosmoInlineAssistantModelsTests.swift`
- Test `Tests/CosmoOSTests/CosmoEditableSurfaceRegistryTests.swift`
- Test `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`
- Test `Tests/CosmoOSTests/CosmoWorkspaceEditApplicatorTests.swift`
- Test `Tests/CosmoOSTests/CosmoInlineAssistantToolTests.swift`
- Test `Tests/CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests.swift`

## Task 1: Core Proposal Models and Diff Engine

**Files:**
- Create: `UI/InlineAssistant/CosmoInlineAssistantModels.swift`
- Create: `UI/InlineAssistant/CosmoInlineAssistantDiffEngine.swift`
- Test: `Tests/CosmoOSTests/CosmoInlineAssistantModelsTests.swift`

- [ ] **Step 1: Write failing tests for proposal operation identity, status, and source hash guards**

Create `Tests/CosmoOSTests/CosmoInlineAssistantModelsTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoInlineAssistantModelsTests: XCTestCase {
    func testOperationAcceptabilityRequiresPendingStatusAndMatchingSourceHash() {
        let source = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Launch note",
            text: "Rent: $4,556/mo",
            sourceHash: "hash-1",
            anchors: [.init(id: "line-1", label: "Line 1", utf16Start: 0, utf16Length: 15)]
        )
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "note:abc:body",
            anchorID: "line-1",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "hash-1",
            rationale: "Use the requested rent number."
        )

        XCTAssertTrue(operation.canApply(against: source))
        XCTAssertFalse(operation.marked(.accepted).canApply(against: source))
        XCTAssertFalse(operation.canApply(against: source.withSourceHash("hash-2")))
    }

    func testDiffEngineBuildsParagraphReplacementHunks() {
        let hunks = CosmoInlineAssistantDiffEngine.hunks(
            original: "Rent: $4,556/mo\nExpenses: $1,800/mo",
            proposed: "Rent: $5,000/mo\nExpenses: $2,100/mo"
        )

        XCTAssertEqual(hunks.map(\.kind), [.removed, .added, .removed, .added])
        XCTAssertEqual(hunks[0].text, "Rent: $4,556/mo")
        XCTAssertEqual(hunks[1].text, "Rent: $5,000/mo")
        XCTAssertEqual(hunks[2].text, "Expenses: $1,800/mo")
        XCTAssertEqual(hunks[3].text, "Expenses: $2,100/mo")
    }
}
```

- [ ] **Step 2: Run the model tests and verify they fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantModelsTests
```

Expected: FAIL because the inline assistant model files do not exist.

- [ ] **Step 3: Add proposal models**

Create `UI/InlineAssistant/CosmoInlineAssistantModels.swift`:

```swift
import Foundation
import CoreGraphics

enum CosmoInlineAssistantRoute: String, Codable, Equatable, Sendable {
    case action
    case answer
}

enum CosmoEditableSurfaceKind: String, Codable, Equatable, Sendable {
    case text
    case structured
    case canvas
}

enum CosmoProposalStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case rejected
    case conflicted
    case applied
}

enum CosmoProposalHunkKind: String, Codable, Equatable, Sendable {
    case context
    case removed
    case added
}

struct CosmoProposalHunk: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: CosmoProposalHunkKind
    var text: String

    init(id: UUID = UUID(), kind: CosmoProposalHunkKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

struct CosmoEditableAnchor: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var label: String
    var utf16Start: Int
    var utf16Length: Int
}

struct CosmoEditableSourceSnapshot: Codable, Equatable, Sendable {
    var surfaceID: String
    var targetID: String
    var kind: CosmoEditableSurfaceKind
    var title: String
    var text: String
    var sourceHash: String
    var anchors: [CosmoEditableAnchor]

    func withSourceHash(_ nextHash: String) -> CosmoEditableSourceSnapshot {
        var copy = self
        copy.sourceHash = nextHash
        return copy
    }
}

enum CosmoAssistantProposalOperationKind: String, Codable, Equatable, Sendable {
    case textReplacement
    case textInsertion
    case structuredFieldReplacement
    case canvasPlan
}

struct CosmoAssistantProposalOperation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: CosmoAssistantProposalOperationKind
    var targetID: String
    var anchorID: String?
    var originalText: String?
    var proposedText: String?
    var sourceHash: String
    var rationale: String
    var status: CosmoProposalStatus
    var canvasPayload: [String: String]

    init(
        id: UUID = UUID(),
        kind: CosmoAssistantProposalOperationKind,
        targetID: String,
        anchorID: String?,
        originalText: String?,
        proposedText: String?,
        sourceHash: String,
        rationale: String,
        status: CosmoProposalStatus = .pending,
        canvasPayload: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.anchorID = anchorID
        self.originalText = originalText
        self.proposedText = proposedText
        self.sourceHash = sourceHash
        self.rationale = rationale
        self.status = status
        self.canvasPayload = canvasPayload
    }

    static func textReplacement(
        targetID: String,
        anchorID: String,
        originalText: String,
        proposedText: String,
        sourceHash: String,
        rationale: String
    ) -> CosmoAssistantProposalOperation {
        CosmoAssistantProposalOperation(
            kind: .textReplacement,
            targetID: targetID,
            anchorID: anchorID,
            originalText: originalText,
            proposedText: proposedText,
            sourceHash: sourceHash,
            rationale: rationale
        )
    }

    func marked(_ nextStatus: CosmoProposalStatus) -> CosmoAssistantProposalOperation {
        var copy = self
        copy.status = nextStatus
        return copy
    }

    func canApply(against source: CosmoEditableSourceSnapshot) -> Bool {
        status == .pending && targetID == source.targetID && sourceHash == source.sourceHash
    }

    var hunks: [CosmoProposalHunk] {
        CosmoInlineAssistantDiffEngine.hunks(
            original: originalText ?? "",
            proposed: proposedText ?? ""
        )
    }
}

struct CosmoAssistantProposal: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var prompt: String
    var surfaceID: String
    var title: String
    var summary: String
    var operations: [CosmoAssistantProposalOperation]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        surfaceID: String,
        title: String,
        summary: String,
        operations: [CosmoAssistantProposalOperation],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.surfaceID = surfaceID
        self.title = title
        self.summary = summary
        self.operations = operations
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Add deterministic hunk generation**

Create `UI/InlineAssistant/CosmoInlineAssistantDiffEngine.swift`:

```swift
import Foundation

enum CosmoInlineAssistantDiffEngine {
    static func hunks(original: String, proposed: String) -> [CosmoProposalHunk] {
        let originalLines = normalizedLines(original)
        let proposedLines = normalizedLines(proposed)
        let maxCount = max(originalLines.count, proposedLines.count)
        var hunks: [CosmoProposalHunk] = []

        for index in 0..<maxCount {
            let oldLine = index < originalLines.count ? originalLines[index] : nil
            let newLine = index < proposedLines.count ? proposedLines[index] : nil

            switch (oldLine, newLine) {
            case let (.some(old), .some(new)) where old == new:
                hunks.append(CosmoProposalHunk(kind: .context, text: old))
            case let (.some(old), .some(new)):
                hunks.append(CosmoProposalHunk(kind: .removed, text: old))
                hunks.append(CosmoProposalHunk(kind: .added, text: new))
            case let (.some(old), .none):
                hunks.append(CosmoProposalHunk(kind: .removed, text: old))
            case let (.none, .some(new)):
                hunks.append(CosmoProposalHunk(kind: .added, text: new))
            case (.none, .none):
                break
            }
        }

        return hunks
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
```

- [ ] **Step 5: Re-run the model tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantModelsTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/InlineAssistant/CosmoInlineAssistantModels.swift UI/InlineAssistant/CosmoInlineAssistantDiffEngine.swift Tests/CosmoOSTests/CosmoInlineAssistantModelsTests.swift
git commit -m "feat: add inline assistant proposal models"
```

## Task 2: Editable Surface Provider Registry

**Files:**
- Create: `UI/InlineAssistant/CosmoEditableSurfaceProvider.swift`
- Create: `UI/InlineAssistant/CosmoEditableSurfaceRegistry.swift`
- Test: `Tests/CosmoOSTests/CosmoEditableSurfaceRegistryTests.swift`

- [ ] **Step 1: Write failing registry tests**

Create `Tests/CosmoOSTests/CosmoEditableSurfaceRegistryTests.swift`:

```swift
import XCTest
@testable import CosmoOS

@MainActor
final class CosmoEditableSurfaceRegistryTests: XCTestCase {
    func testRegistryReturnsMostRecentActiveProvider() async throws {
        let registry = CosmoEditableSurfaceRegistry()
        let first = TestEditableSurface(surfaceID: "note:1", targetID: "note:1:body", title: "First")
        let second = TestEditableSurface(surfaceID: "content:2", targetID: "content:2:draft", title: "Second")

        registry.register(first)
        XCTAssertEqual(registry.activeSurface?.surfaceID, "note:1")

        registry.register(second)
        XCTAssertEqual(registry.activeSurface?.surfaceID, "content:2")

        registry.unregister(surfaceID: "content:2")
        XCTAssertEqual(registry.activeSurface?.surfaceID, "note:1")
    }

    func testSnapshotContainsStableHash() {
        let surface = TestEditableSurface(surfaceID: "note:1", targetID: "note:1:body", title: "Note")
        let snapshot = surface.editableSnapshot()

        XCTAssertEqual(snapshot.sourceHash, CosmoEditableSurfaceHasher.hash("Original text"))
        XCTAssertEqual(snapshot.anchors.first?.id, "body")
    }
}

@MainActor
private final class TestEditableSurface: CosmoEditableSurfaceProvider {
    let surfaceID: String
    let targetID: String
    let title: String

    init(surfaceID: String, targetID: String, title: String) {
        self.surfaceID = surfaceID
        self.targetID = targetID
        self.title = title
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: targetID,
            kind: .text,
            title: title,
            text: "Original text",
            sourceHash: CosmoEditableSurfaceHasher.hash("Original text"),
            anchors: [.init(id: "body", label: "Body", utf16Start: 0, utf16Length: 13)]
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }
}
```

- [ ] **Step 2: Run the registry tests and verify they fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoEditableSurfaceRegistryTests
```

Expected: FAIL because registry types do not exist.

- [ ] **Step 3: Add provider protocol and operation result**

Create `UI/InlineAssistant/CosmoEditableSurfaceProvider.swift`:

```swift
import Foundation

struct CosmoEditableOperationResult: Equatable, Sendable {
    var operationID: UUID
    var status: CosmoProposalStatus
    var message: String
}

@MainActor
protocol CosmoEditableSurfaceProvider: AnyObject {
    var surfaceID: String { get }
    func editableSnapshot() -> CosmoEditableSourceSnapshot
    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult
    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult
}

enum CosmoEditableSurfaceHasher {
    static func hash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
```

- [ ] **Step 4: Add active surface registry**

Create `UI/InlineAssistant/CosmoEditableSurfaceRegistry.swift`:

```swift
import Foundation

@MainActor
final class CosmoEditableSurfaceRegistry {
    static let shared = CosmoEditableSurfaceRegistry()

    private var providers: [String: WeakEditableSurfaceProvider] = [:]
    private var activationOrder: [String] = []

    var activeSurface: (any CosmoEditableSurfaceProvider)? {
        cleanupReleasedProviders()
        return activationOrder.reversed().compactMap { providers[$0]?.provider }.first
    }

    func register(_ provider: any CosmoEditableSurfaceProvider) {
        providers[provider.surfaceID] = WeakEditableSurfaceProvider(provider)
        activationOrder.removeAll { $0 == provider.surfaceID }
        activationOrder.append(provider.surfaceID)
    }

    func activate(surfaceID: String) {
        guard providers[surfaceID]?.provider != nil else { return }
        activationOrder.removeAll { $0 == surfaceID }
        activationOrder.append(surfaceID)
    }

    func unregister(surfaceID: String) {
        providers.removeValue(forKey: surfaceID)
        activationOrder.removeAll { $0 == surfaceID }
    }

    private func cleanupReleasedProviders() {
        let released = providers.compactMap { key, value in value.provider == nil ? key : nil }
        for key in released {
            providers.removeValue(forKey: key)
            activationOrder.removeAll { $0 == key }
        }
    }
}

private final class WeakEditableSurfaceProvider {
    weak var provider: (any CosmoEditableSurfaceProvider)?

    init(_ provider: any CosmoEditableSurfaceProvider) {
        self.provider = provider
    }
}
```

- [ ] **Step 5: Re-run the registry tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoEditableSurfaceRegistryTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/InlineAssistant/CosmoEditableSurfaceProvider.swift UI/InlineAssistant/CosmoEditableSurfaceRegistry.swift Tests/CosmoOSTests/CosmoEditableSurfaceRegistryTests.swift
git commit -m "feat: register editable assistant surfaces"
```

## Task 3: Agent Tool Contract for Reviewed Workspace Edits

**Files:**
- Modify: `Agent/Core/AgentToolRegistry.swift`
- Modify: `Agent/Core/AgentToolExecutor.swift`
- Create: `Tests/CosmoOSTests/CosmoInlineAssistantToolTests.swift`

- [ ] **Step 1: Write failing tool registration test**

Create `Tests/CosmoOSTests/CosmoInlineAssistantToolTests.swift`:

```swift
import XCTest
@testable import CosmoOS

@MainActor
final class CosmoInlineAssistantToolTests: XCTestCase {
    func testInlineAssistantToolsAreRegisteredForInAppAgentUse() {
        let tools = AgentToolRegistry.shared.toolsForIntent(
            .execute,
            source: .inApp,
            profileBundles: [],
            forcedBundles: [.workspaceEditing]
        )
        XCTAssertTrue(tools.contains { $0.name == "propose_workspace_edit" })
        XCTAssertTrue(tools.contains { $0.name == "answer_in_assistant_pane" })
    }

    func testProposeWorkspaceEditCallbackReceivesProposal() async throws {
        let executor = AgentToolExecutor.shared
        var received: CosmoAssistantProposal?
        executor.onWorkspaceEditProposal = { proposal in
            received = proposal
        }

        let result = try await executor.execute(
            toolName: "propose_workspace_edit",
            arguments: [
                "prompt": "replace rent",
                "surfaceID": "note:abc",
                "title": "Slide 4 numbers",
                "summary": "Updated rent number",
                "operations": [[
                    "kind": "textReplacement",
                    "targetID": "note:abc:body",
                    "anchorID": "line-1",
                    "originalText": "Rent: $4,556/mo",
                    "proposedText": "Rent: $5,000/mo",
                    "sourceHash": "hash-1",
                    "rationale": "Use requested rent."
                ]]
            ]
        )

        XCTAssertTrue(result.contains("\"success\":true"))
        XCTAssertEqual(received?.operations.count, 1)
        XCTAssertEqual(received?.operations.first?.proposedText, "Rent: $5,000/mo")
        executor.onWorkspaceEditProposal = nil
    }
}
```

- [ ] **Step 2: Run the tool tests and verify they fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantToolTests
```

Expected: FAIL because `.workspaceEditing`, `propose_workspace_edit`, and callbacks do not exist.

- [ ] **Step 3: Add workspace editing tool bundle**

In `UI/CosmoWindow/CollaboratorModels.swift`, extend `AgentToolBundle` with:

```swift
case workspaceEditing
```

In `UI/CosmoWindow/CollaboratorModels.swift`, add `.workspaceEditing` to the existing `AgentToolBundle` enum and update each switch:

```swift
var displayName: String {
    switch self {
    case .workspaceEditing:
        return "Workspace Editing"
    case .webResearch: return "Web Research"
    case .contentSearch: return "Content Search"
    case .clientProfiles: return "Client Profiles"
    case .clientMemory: return "Client Memory"
    case .swipes: return "Swipes"
    case .writing: return "Writing"
    case .strategy: return "Strategy"
    case .canvasSpatial: return "Canvas Spatial"
    case .scheduling: return "Scheduling"
    case .analytics: return "Analytics"
    case .preferences: return "Preferences"
    }
}

var icon: String {
    switch self {
    case .workspaceEditing: return "text.badge.checkmark"
    case .webResearch: return "globe"
    case .contentSearch: return "doc.text.magnifyingglass"
    case .clientProfiles: return "person.crop.rectangle.stack"
    case .clientMemory: return "person.badge.clock"
    case .swipes: return "rectangle.stack"
    case .writing: return "pencil.and.scribble"
    case .strategy: return "point.3.connected.trianglepath.dotted"
    case .canvasSpatial: return "square.grid.3x3"
    case .scheduling: return "calendar"
    case .analytics: return "chart.bar"
    case .preferences: return "slider.horizontal.3"
    }
}

var accessDescription: String {
    switch self {
    case .workspaceEditing:
        return "Lets the agent stage reviewed edits for the active document, focus mode, structured fields, or canvas without directly applying changes."
    case .webResearch:
        return "Lets the agent search the web for current information, sources, stats, market examples, and facts outside your local Cosmo database."
    case .contentSearch:
        return "Lets the agent search, read, create, and update Cosmo ideas, content, captures, and thinkspaces."
    case .clientProfiles:
        return "Lets the agent list and read client profiles, voice notes, brand angles, audience models, and client-tagged work."
    case .clientMemory:
        return "Lets the agent read and update persistent client-specific memory such as preferences, voice quirks, forbidden patterns, and learned rules."
    case .swipes:
        return "Lets the agent search, browse, filter, analyze, score, and adapt your swipe library and hook/framework references."
    case .writing:
        return "Lets the agent use Cosmo writing tools for outlines, drafts, hooks, revisions, and content generation instead of only replying inline."
    case .strategy:
        return "Lets the agent use strategy, intelligence, insight memory, lessons, and module suggestion tools for higher-level planning and synthesis."
    case .canvasSpatial:
        return "Lets the agent inspect the current thinkspace and propose reviewable canvas plans for arranging, placing, creating, moving, and resizing blocks."
    case .scheduling:
        return "Lets the agent read and modify calendar blocks, schedule blocks, tasks, and unscheduled work."
    case .analytics:
        return "Lets the agent access performance, scoring, XP, analytics, and aggregate signals for prioritization and review."
    case .preferences:
        return "Lets the agent read and update global preferences, standing instructions, and long-term behavioral guidance."
    }
}
```

- [ ] **Step 4: Add tool definitions**

In `Agent/Core/AgentToolRegistry.swift`, add:

```swift
private var workspaceEditingTools: [LLMToolDefinition] {
    [
        LLMToolDefinition(
            name: "propose_workspace_edit",
            description: "Stage reviewed edits for the active Cosmo surface. Use this for document edits, number replacements, hook changes, outline changes, and structured field changes. This tool never applies changes; it only creates a user-reviewed proposal.",
            parametersSchema: [
                "type": "object",
                "properties": [
                    "prompt": ["type": "string", "description": "The user's original instruction"] as [String: Any],
                    "surfaceID": ["type": "string", "description": "Editable surface id from active context"] as [String: Any],
                    "title": ["type": "string", "description": "Short proposal title"] as [String: Any],
                    "summary": ["type": "string", "description": "One sentence describing the proposed changes"] as [String: Any],
                    "operations": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "kind": ["type": "string", "enum": ["textReplacement", "textInsertion", "structuredFieldReplacement", "canvasPlan"]] as [String: Any],
                                "targetID": ["type": "string"] as [String: Any],
                                "anchorID": ["type": "string"] as [String: Any],
                                "originalText": ["type": "string"] as [String: Any],
                                "proposedText": ["type": "string"] as [String: Any],
                                "sourceHash": ["type": "string"] as [String: Any],
                                "rationale": ["type": "string"] as [String: Any]
                            ] as [String: Any],
                            "required": ["kind", "targetID", "sourceHash", "rationale"]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "required": ["prompt", "surfaceID", "title", "summary", "operations"]
            ]
        ),
        LLMToolDefinition(
            name: "answer_in_assistant_pane",
            description: "Send a conversational answer to the assistant pane. Use this for questions, explanations, analysis, or any request that does not need reviewed edits.",
            parametersSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Short answer title"] as [String: Any],
                    "answer": ["type": "string", "description": "Assistant response body"] as [String: Any]
                ] as [String: Any],
                "required": ["answer"]
            ]
        )
    ]
}
```

In `Agent/Core/AgentToolRegistry.swift`, update `tools(forBundles:source:)`:

```swift
case .workspaceEditing:
    tools += workspaceEditingTools
```

- [ ] **Step 5: Add executor callbacks and handlers**

In `Agent/Core/AgentToolExecutor.swift`, add properties near `onCanvasPlan`:

```swift
var onWorkspaceEditProposal: ((CosmoAssistantProposal) -> Void)?
var onAssistantPaneAnswer: ((_ title: String?, _ answer: String) -> Void)?
```

Add cases in `execute(toolName:arguments:)`:

```swift
case "propose_workspace_edit": return try await proposeWorkspaceEdit(arguments)
case "answer_in_assistant_pane": return try await answerInAssistantPane(arguments)
```

Add handlers:

```swift
private func proposeWorkspaceEdit(_ args: [String: Any]) async throws -> String {
    guard let prompt = args["prompt"] as? String,
          let surfaceID = args["surfaceID"] as? String,
          let title = args["title"] as? String,
          let summary = args["summary"] as? String,
          let rawOperations = args["operations"] as? [[String: Any]] else {
        return jsonError("Missing required workspace edit proposal fields")
    }

    let operations = rawOperations.map { raw -> CosmoAssistantProposalOperation in
        CosmoAssistantProposalOperation(
            kind: CosmoAssistantProposalOperationKind(rawValue: raw["kind"] as? String ?? "") ?? .textReplacement,
            targetID: raw["targetID"] as? String ?? "",
            anchorID: raw["anchorID"] as? String,
            originalText: raw["originalText"] as? String,
            proposedText: raw["proposedText"] as? String,
            sourceHash: raw["sourceHash"] as? String ?? "",
            rationale: raw["rationale"] as? String ?? "Proposed by Cosmo."
        )
    }

    let proposal = CosmoAssistantProposal(
        prompt: prompt,
        surfaceID: surfaceID,
        title: title,
        summary: summary,
        operations: operations
    )
    onWorkspaceEditProposal?(proposal)

    return jsonEncode([
        "success": true,
        "proposalId": proposal.id.uuidString,
        "operationCount": operations.count,
        "message": "Workspace edit proposal is ready for review. Do not say it has been applied until the user accepts changes."
    ] as [String: Any])
}

private func answerInAssistantPane(_ args: [String: Any]) async throws -> String {
    guard let answer = args["answer"] as? String else {
        return jsonError("Missing required parameter: answer")
    }
    onAssistantPaneAnswer?(args["title"] as? String, answer)
    return jsonEncode(["success": true, "message": "Answer sent to assistant pane"])
}
```

- [ ] **Step 6: Re-run tool tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantToolTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/CosmoWindow/CollaboratorModels.swift Agent/Core/AgentToolRegistry.swift Agent/Core/AgentToolExecutor.swift Tests/CosmoOSTests/CosmoInlineAssistantToolTests.swift
git commit -m "feat: add reviewed workspace edit tools"
```

## Task 4: Inline Assistant Store and Agent Bridge

**Files:**
- Create: `UI/InlineAssistant/CosmoInlineAssistantStore.swift`
- Create: `UI/InlineAssistant/CosmoInlineAssistantAgentBridge.swift`
- Test: `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`

- [ ] **Step 1: Write failing route tests**

Create `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`:

```swift
import XCTest
@testable import CosmoOS

@MainActor
final class CosmoInlineAssistantRoutingTests: XCTestCase {
    func testQuestionPromptPrefersPaneRoute() {
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "What is the strongest hook here?"), .answer)
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Explain why slide 4 works"), .answer)
    }

    func testEditPromptPrefersActionRoute() {
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Replace the numbers in slide 4"), .action)
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Organize this canvas"), .action)
        XCTAssertEqual(CosmoInlineAssistantPromptClassifier.route(for: "Rewrite this paragraph to be sharper"), .action)
    }

    func testReceivingProposalKeepsPaneClosed() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        let proposal = CosmoAssistantProposal(
            prompt: "Replace rent",
            surfaceID: "note:abc",
            title: "Numbers",
            summary: "Update rent",
            operations: []
        )

        store.receive(proposal: proposal)

        XCTAssertEqual(store.proposals.count, 1)
        XCTAssertFalse(store.isPaneRequested)
    }

    func testReceivingAnswerRequestsPane() {
        let store = CosmoInlineAssistantStore(agentBridge: .mock)
        store.receivePaneAnswer(title: "Answer", answer: "This hook works because it creates contrast.")

        XCTAssertTrue(store.isPaneRequested)
        XCTAssertEqual(store.paneMessages.last?.content, "This hook works because it creates contrast.")
    }
}
```

- [ ] **Step 2: Run routing tests and verify they fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests
```

Expected: FAIL because store and classifier do not exist.

- [ ] **Step 3: Add prompt classifier and pane message model**

Create `UI/InlineAssistant/CosmoInlineAssistantStore.swift` with:

```swift
import Foundation
import Combine

struct CosmoInlineAssistantPaneMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
        case system
    }

    var id = UUID()
    var role: Role
    var content: String
    var createdAt = Date()
}

enum CosmoInlineAssistantPromptClassifier {
    static func route(for prompt: String) -> CosmoInlineAssistantRoute {
        let lower = prompt.lowercased()
        let actionWords = [
            "replace", "rewrite", "edit", "insert", "append", "organize",
            "move", "cluster", "reorder", "clean up", "turn this into",
            "change", "fix", "apply", "update"
        ]
        if actionWords.contains(where: { lower.contains($0) }) {
            return .action
        }
        return .answer
    }
}

@MainActor
final class CosmoInlineAssistantStore: ObservableObject {
    @Published var composerText = ""
    @Published var isProcessing = false
    @Published var statusText: String?
    @Published var proposals: [CosmoAssistantProposal] = []
    @Published var paneMessages: [CosmoInlineAssistantPaneMessage] = []
    @Published var isPaneRequested = false
    @Published var errorText: String?

    private let agentBridge: CosmoInlineAssistantAgentBridge

    init(agentBridge: CosmoInlineAssistantAgentBridge = .live) {
        self.agentBridge = agentBridge
    }

    func submit() async {
        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        composerText = ""
        errorText = nil
        isProcessing = true
        statusText = "Analyzing context"

        let route = CosmoInlineAssistantPromptClassifier.route(for: prompt)
        if route == .answer {
            isPaneRequested = true
        }

        paneMessages.append(.init(role: .user, content: prompt))

        do {
            try await agentBridge.send(prompt: prompt, route: route, store: self)
        } catch {
            errorText = error.localizedDescription
        }

        isProcessing = false
        statusText = nil
    }

    func receive(proposal: CosmoAssistantProposal) {
        proposals.append(proposal)
        isPaneRequested = false
    }

    func receivePaneAnswer(title: String?, answer: String) {
        isPaneRequested = true
        paneMessages.append(.init(role: .assistant, content: answer))
    }

    func dismissPaneRequest() {
        isPaneRequested = false
    }
}
```

- [ ] **Step 4: Add agent bridge**

Create `UI/InlineAssistant/CosmoInlineAssistantAgentBridge.swift`:

```swift
import Foundation

struct CosmoInlineAssistantAgentBridge {
    var send: @MainActor (_ prompt: String, _ route: CosmoInlineAssistantRoute, _ store: CosmoInlineAssistantStore) async throws -> Void

    static let live = CosmoInlineAssistantAgentBridge { prompt, route, store in
        let executor = AgentToolExecutor.shared
        executor.onWorkspaceEditProposal = { proposal in
            Task { @MainActor in
                store.receive(proposal: proposal)
            }
        }
        executor.onAssistantPaneAnswer = { title, answer in
            Task { @MainActor in
                store.receivePaneAnswer(title: title, answer: answer)
            }
        }

        defer {
            executor.onWorkspaceEditProposal = nil
            executor.onAssistantPaneAnswer = nil
        }

        let activeSurface = CosmoEditableSurfaceRegistry.shared.activeSurface
        let snapshot = activeSurface?.editableSnapshot()
        let surfaceContext = snapshot.map { snapshot in
            """
            Active editable surface:
            surfaceID: \(snapshot.surfaceID)
            targetID: \(snapshot.targetID)
            title: \(snapshot.title)
            kind: \(snapshot.kind.rawValue)
            sourceHash: \(snapshot.sourceHash)
            text:
            \(snapshot.text)
            """
        } ?? "No editable surface is currently registered."

        let routeInstruction: String
        switch route {
        case .action:
            routeInstruction = "If the user is asking for edits, call propose_workspace_edit with exact source hashes and reviewed operations."
        case .answer:
            routeInstruction = "If answering a question, call answer_in_assistant_pane with the response."
        }

        let systemPrompt = [
            "You are Cosmo's inline workspace assistant.",
            routeInstruction,
            "Never mutate app state directly. All edits must be proposal operations.",
            surfaceContext
        ].joined(separator: "\n\n")

        _ = await CosmoAgentService.shared.processMessage(
            prompt,
            conversationId: "cosmo-inline-assistant",
            source: .inApp,
            tierOverride: CosmoWindowViewModel.shared.modelOverride,
            systemPromptOverride: systemPrompt,
            responseMode: .automatic,
            profileToolBundles: [],
            forcedToolBundles: [.workspaceEditing]
        )
    }

    static let mock = CosmoInlineAssistantAgentBridge { _, _, _ in }
}
```

- [ ] **Step 5: Re-run routing tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/InlineAssistant/CosmoInlineAssistantStore.swift UI/InlineAssistant/CosmoInlineAssistantAgentBridge.swift Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift
git commit -m "feat: route inline assistant prompts"
```

## Task 5: Pane Integration

**Files:**
- Create: `UI/InlineAssistant/CosmoInlineAssistantPaneView.swift`
- Modify: `Navigation/PaneManager.swift`
- Modify: `Navigation/PaneContentView.swift`
- Modify: `Core/CosmoNotifications.swift`
- Test: `Tests/CosmoOSTests/PaneManagerInlineAssistantPaneTests.swift`

- [ ] **Step 1: Write failing pane manager tests**

Create `Tests/CosmoOSTests/PaneManagerInlineAssistantPaneTests.swift`:

```swift
import XCTest
@testable import CosmoOS

@MainActor
final class PaneManagerInlineAssistantPaneTests: XCTestCase {
    func testInlineAssistantPaneHasStableIDAndMinimalChrome() {
        let content = PaneContent.inlineAssistant
        XCTAssertEqual(content.id, "inlineAssistant")
        XCTAssertEqual(content.chromeStyle, .minimal)
    }

    func testOpenOrActivateInlineAssistantDoesNotDuplicatePane() {
        let manager = PaneManager()
        manager.openOrActivateInlineAssistant()
        manager.openOrActivateInlineAssistant()

        XCTAssertEqual(manager.panes.filter { $0.id == "inlineAssistant" }.count, 1)
        XCTAssertEqual(manager.activePaneId, "inlineAssistant")
    }
}
```

- [ ] **Step 2: Run pane tests and verify they fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/PaneManagerInlineAssistantPaneTests
```

Expected: FAIL because `.inlineAssistant` does not exist.

- [ ] **Step 3: Extend pane content**

In `Navigation/PaneManager.swift`, add case:

```swift
case inlineAssistant
```

Update `id`:

```swift
case .inlineAssistant:
    return "inlineAssistant"
```

Update `entityId`, `entitySelection`, `thinkspaceId`, `webURL`, and `collaborationTarget` nil branches to include `.inlineAssistant`.

Update `chromeStyle`:

```swift
case .cosmoWindow, .collaborator, .inlineAssistant:
    return .minimal
```

Add helper:

```swift
func openOrActivateInlineAssistant() {
    let content = PaneContent.inlineAssistant
    if panes.contains(where: { $0.id == content.id }) {
        activatePane(content.id)
    } else {
        openPane(content)
    }
}
```

- [ ] **Step 4: Add pane view**

Create `UI/InlineAssistant/CosmoInlineAssistantPaneView.swift`:

```swift
import SwiftUI

struct CosmoInlineAssistantPaneView: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.accent)
                Text("Cosmo Assistant")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.text)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close assistant pane")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.paneMessages) { message in
                        CosmoInlineAssistantPaneMessageRow(message: message)
                    }
                }
                .padding(16)
            }

            HStack(spacing: 10) {
                TextField("Ask Cosmo", text: $store.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                Button {
                    Task { await store.submit() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
            }
            .padding(12)
            .background(DS.surfaceCard, in: .rect(cornerRadius: 14))
            .overlay(.rect(cornerRadius: 14).stroke(DS.borderSubtle, lineWidth: 1))
            .padding(16)
        }
        .background(DS.bg)
    }
}

private struct CosmoInlineAssistantPaneMessageRow: View {
    let message: CosmoInlineAssistantPaneMessage

    var body: some View {
        Text(message.content)
            .font(.system(size: 14))
            .foregroundStyle(message.role == .user ? DS.text : DS.textSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role == .user ? DS.accentSoft : DS.surfaceCard, in: .rect(cornerRadius: 12))
    }
}
```

- [ ] **Step 5: Render pane content**

In `Navigation/PaneContentView.swift`, add the switch case:

```swift
case .inlineAssistant:
    CosmoInlineAssistantPaneView(store: CosmoInlineAssistantStore.shared, onClose: onClose)
        .environment(\.isPaneContext, true)
        .environment(\.isPaneActive, isActive)
        .environment(\.isPaneContextOwner, isContextOwner)
```

If `CosmoInlineAssistantStore.shared` does not exist, add this static singleton to `CosmoInlineAssistantStore`:

```swift
static let shared = CosmoInlineAssistantStore()
```

- [ ] **Step 6: Add notification names**

In `Core/CosmoNotifications.swift`, add:

```swift
static let openInlineAssistant = Notification.Name("com.cosmo.navigation.openInlineAssistant")
static let openInlineAssistantPane = Notification.Name("com.cosmo.navigation.openInlineAssistantPane")
```

Place these inside the existing navigation notification namespace.

- [ ] **Step 7: Re-run pane tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/PaneManagerInlineAssistantPaneTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Navigation/PaneManager.swift Navigation/PaneContentView.swift Core/CosmoNotifications.swift UI/InlineAssistant/CosmoInlineAssistantPaneView.swift Tests/CosmoOSTests/PaneManagerInlineAssistantPaneTests.swift
git commit -m "feat: add inline assistant pane"
```

## Task 6: Bottom Assistant Composer Overlay

**Files:**
- Create: `UI/InlineAssistant/CosmoInlineAssistantBar.swift`
- Modify: `Navigation/MainView.swift`
- Test: `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`

- [ ] **Step 1: Add store state tests for pane button**

Append to `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`:

```swift
func testPaneButtonRequestsPaneWithoutSubmittingPrompt() {
    let store = CosmoInlineAssistantStore(agentBridge: .mock)
    store.requestPane()
    XCTAssertTrue(store.isPaneRequested)
}
```

- [ ] **Step 2: Run route tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests
```

Expected: FAIL because `requestPane()` does not exist.

- [ ] **Step 3: Add pane request method**

In `CosmoInlineAssistantStore`, add:

```swift
func requestPane() {
    isPaneRequested = true
}
```

- [ ] **Step 4: Add bottom composer view**

Create `UI/InlineAssistant/CosmoInlineAssistantBar.swift`:

```swift
import SwiftUI

struct CosmoInlineAssistantBar: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onOpenPane: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 34, height: 34)

            TextField("Describe changes you want to make", text: $store.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...4)

            if let status = store.statusText {
                Text(status)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }

            Button(action: onOpenPane) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open assistant pane")

            Button {
                Task { await store.submit() }
            } label: {
                Image(systemName: store.isProcessing ? "stop.fill" : "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DS.borderSubtle : DS.accent, in: Circle())
                    .foregroundStyle(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DS.textMuted : DS.textOnAccent)
            }
            .buttonStyle(.plain)
            .disabled(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isProcessing)
            .accessibilityLabel("Send assistant prompt")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 640)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 24))
        .overlay(.rect(cornerRadius: 24).stroke(DS.borderSubtle, lineWidth: 1))
        .dsFloatingShadow()
    }
}
```

- [ ] **Step 5: Render overlay in MainView**

In `Navigation/MainView.swift`, add state:

```swift
@StateObject private var inlineAssistantStore = CosmoInlineAssistantStore.shared
```

Inside the root `ZStack`, above global status indicators and below modal overlays, add:

```swift
VStack {
    Spacer()
    CosmoInlineAssistantBar(store: inlineAssistantStore) {
        inlineAssistantStore.requestPane()
        withAnimation(ProMotionSprings.snappy) {
            paneManager.openOrActivateInlineAssistant()
        }
    }
    .padding(.bottom, 24)
}
.zIndex(55)
```

Add an `onChange` for pane requests:

```swift
.onChange(of: inlineAssistantStore.isPaneRequested) { _, requested in
    guard requested else { return }
    withAnimation(ProMotionSprings.snappy) {
        paneManager.openOrActivateInlineAssistant()
    }
    inlineAssistantStore.dismissPaneRequest()
}
```

- [ ] **Step 6: Re-run route tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests
```

Expected: PASS.

- [ ] **Step 7: Manually verify composer layout**

Run the app:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: Build exits 0. In the running app, the assistant bar appears bottom-center, does not cover pane resize handles, and the pane icon opens the right pane.

- [ ] **Step 8: Commit**

```bash
git add UI/InlineAssistant/CosmoInlineAssistantBar.swift Navigation/MainView.swift Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift
git commit -m "feat: add bottom inline assistant composer"
```

## Task 7: Editor Applicator and Anchored Text Operations

**Files:**
- Create: `UI/InlineAssistant/CosmoWorkspaceEditApplicator.swift`
- Modify: `Editor/EditorCommandBus.swift`
- Test: `Tests/CosmoOSTests/CosmoWorkspaceEditApplicatorTests.swift`

- [ ] **Step 1: Write failing applicator tests**

Create `Tests/CosmoOSTests/CosmoWorkspaceEditApplicatorTests.swift`:

```swift
import XCTest
@testable import CosmoOS

@MainActor
final class CosmoWorkspaceEditApplicatorTests: XCTestCase {
    func testApplicatorRejectsSourceHashMismatch() async throws {
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Note",
            text: "Rent: $4,556/mo",
            sourceHash: "hash-current",
            anchors: [.init(id: "line-1", label: "Line 1", utf16Start: 0, utf16Length: 15)]
        )
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "note:abc:body",
            anchorID: "line-1",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "hash-old",
            rationale: "Update rent."
        )

        let result = await CosmoWorkspaceEditApplicator.validate(operation: operation, against: snapshot)
        XCTAssertEqual(result.status, .conflicted)
    }

    func testApplicatorBuildsReplacementPayloadForMatchingAnchor() async throws {
        let snapshot = CosmoEditableSourceSnapshot(
            surfaceID: "note:abc",
            targetID: "note:abc:body",
            kind: .text,
            title: "Note",
            text: "Rent: $4,556/mo",
            sourceHash: "hash-current",
            anchors: [.init(id: "line-1", label: "Line 1", utf16Start: 0, utf16Length: 15)]
        )
        let operation = CosmoAssistantProposalOperation.textReplacement(
            targetID: "note:abc:body",
            anchorID: "line-1",
            originalText: "Rent: $4,556/mo",
            proposedText: "Rent: $5,000/mo",
            sourceHash: "hash-current",
            rationale: "Update rent."
        )

        let payload = try CosmoWorkspaceEditApplicator.replacementPayload(operation: operation, snapshot: snapshot)
        XCTAssertEqual(payload.targetEditorID, "note:abc:body")
        XCTAssertEqual(payload.utf16Start, 0)
        XCTAssertEqual(payload.utf16Length, 15)
        XCTAssertEqual(payload.replacementText, "Rent: $5,000/mo")
    }
}
```

- [ ] **Step 2: Run applicator tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWorkspaceEditApplicatorTests
```

Expected: FAIL because applicator types do not exist.

- [ ] **Step 3: Add reviewed edit payload to EditorCommandBus**

In `Editor/EditorCommandBus.swift`, add:

```swift
struct EditorReviewedReplacementPayload: Equatable, Sendable {
    var targetEditorID: String
    var utf16Start: Int
    var utf16Length: Int
    var replacementText: String
}
```

Add method:

```swift
func replaceRange(_ payload: EditorReviewedReplacementPayload, allowInactive: Bool = true) {
    NotificationCenter.default.post(
        name: .replaceRangeInEditor,
        object: nil,
        userInfo: [
            "targetEditorID": payload.targetEditorID,
            "utf16Start": payload.utf16Start,
            "utf16Length": payload.utf16Length,
            "replacementText": payload.replacementText,
            "allowInactive": allowInactive
        ]
    )
}
```

Add notification:

```swift
static let replaceRangeInEditor = Notification.Name("com.cosmo.replaceRangeInEditor")
```

- [ ] **Step 4: Add applicator**

Create `UI/InlineAssistant/CosmoWorkspaceEditApplicator.swift`:

```swift
import Foundation

enum CosmoWorkspaceEditApplicatorError: Error, Equatable {
    case missingAnchor
    case missingReplacement
    case sourceConflict
}

enum CosmoWorkspaceEditApplicator {
    static func validate(
        operation: CosmoAssistantProposalOperation,
        against snapshot: CosmoEditableSourceSnapshot
    ) async -> CosmoEditableOperationResult {
        guard operation.canApply(against: snapshot) else {
            return CosmoEditableOperationResult(
                operationID: operation.id,
                status: .conflicted,
                message: "The source changed since Cosmo proposed this edit."
            )
        }

        return CosmoEditableOperationResult(
            operationID: operation.id,
            status: .pending,
            message: "Ready to apply."
        )
    }

    static func replacementPayload(
        operation: CosmoAssistantProposalOperation,
        snapshot: CosmoEditableSourceSnapshot
    ) throws -> EditorReviewedReplacementPayload {
        guard operation.sourceHash == snapshot.sourceHash else {
            throw CosmoWorkspaceEditApplicatorError.sourceConflict
        }
        guard let anchorID = operation.anchorID,
              let anchor = snapshot.anchors.first(where: { $0.id == anchorID }) else {
            throw CosmoWorkspaceEditApplicatorError.missingAnchor
        }
        guard let replacement = operation.proposedText else {
            throw CosmoWorkspaceEditApplicatorError.missingReplacement
        }

        return EditorReviewedReplacementPayload(
            targetEditorID: operation.targetID,
            utf16Start: anchor.utf16Start,
            utf16Length: anchor.utf16Length,
            replacementText: replacement
        )
    }

    static func applyTextOperation(
        _ operation: CosmoAssistantProposalOperation,
        snapshot: CosmoEditableSourceSnapshot
    ) async throws -> CosmoEditableOperationResult {
        let payload = try replacementPayload(operation: operation, snapshot: snapshot)
        await EditorCommandBus.shared.replaceRange(payload, allowInactive: true)
        return CosmoEditableOperationResult(
            operationID: operation.id,
            status: .applied,
            message: "Applied reviewed edit."
        )
    }
}
```

- [ ] **Step 5: Re-run applicator tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWorkspaceEditApplicatorTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/InlineAssistant/CosmoWorkspaceEditApplicator.swift Editor/EditorCommandBus.swift Tests/CosmoOSTests/CosmoWorkspaceEditApplicatorTests.swift
git commit -m "feat: apply reviewed inline assistant text edits"
```

## Task 8: Proposal Review Overlay and Accept/Reject Flow

**Files:**
- Create: `UI/InlineAssistant/CosmoInlineProposalOverlay.swift`
- Modify: `UI/InlineAssistant/CosmoInlineAssistantStore.swift`
- Modify: `Navigation/MainView.swift`
- Test: `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`

- [ ] **Step 1: Add store tests for accept and reject**

Append to `Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift`:

```swift
func testRejectOperationMarksOnlyThatOperationRejected() async {
    let operation = CosmoAssistantProposalOperation.textReplacement(
        targetID: "note:abc:body",
        anchorID: "body",
        originalText: "A",
        proposedText: "B",
        sourceHash: "hash",
        rationale: "Change A to B."
    )
    let proposal = CosmoAssistantProposal(
        prompt: "Change A",
        surfaceID: "note:abc",
        title: "Edit",
        summary: "Edit A",
        operations: [operation]
    )
    let store = CosmoInlineAssistantStore(agentBridge: .mock)
    store.receive(proposal: proposal)
    await store.reject(operationID: operation.id)

    XCTAssertEqual(store.proposals.first?.operations.first?.status, .rejected)
}
```

- [ ] **Step 2: Run route tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests
```

Expected: FAIL because accept/reject methods do not exist.

- [ ] **Step 3: Add accept/reject methods to store**

In `CosmoInlineAssistantStore`, add:

```swift
func reject(operationID: UUID) async {
    updateOperation(operationID: operationID, status: .rejected)
}

func accept(operationID: UUID) async {
    guard let provider = CosmoEditableSurfaceRegistry.shared.activeSurface else {
        updateOperation(operationID: operationID, status: .conflicted)
        return
    }

    for proposalIndex in proposals.indices {
        guard let operationIndex = proposals[proposalIndex].operations.firstIndex(where: { $0.id == operationID }) else {
            continue
        }
        let operation = proposals[proposalIndex].operations[operationIndex]
        do {
            let result = try await provider.apply(operation: operation)
            proposals[proposalIndex].operations[operationIndex].status = result.status
        } catch {
            proposals[proposalIndex].operations[operationIndex].status = .conflicted
        }
        return
    }
}

func acceptAll(proposalID: UUID) async {
    guard let proposal = proposals.first(where: { $0.id == proposalID }) else { return }
    for operation in proposal.operations where operation.status == .pending {
        await accept(operationID: operation.id)
    }
}

func rejectAll(proposalID: UUID) async {
    guard let proposal = proposals.first(where: { $0.id == proposalID }) else { return }
    for operation in proposal.operations where operation.status == .pending {
        await reject(operationID: operation.id)
    }
}

private func updateOperation(operationID: UUID, status: CosmoProposalStatus) {
    for proposalIndex in proposals.indices {
        guard let operationIndex = proposals[proposalIndex].operations.firstIndex(where: { $0.id == operationID }) else {
            continue
        }
        proposals[proposalIndex].operations[operationIndex].status = status
        return
    }
}
```

- [ ] **Step 4: Add review overlay view**

Create `UI/InlineAssistant/CosmoInlineProposalOverlay.swift`:

```swift
import SwiftUI

struct CosmoInlineProposalOverlay: View {
    @ObservedObject var store: CosmoInlineAssistantStore

    private var visibleProposals: [CosmoAssistantProposal] {
        store.proposals.filter { proposal in
            proposal.operations.contains { $0.status == .pending || $0.status == .conflicted }
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            ForEach(visibleProposals) { proposal in
                CosmoInlineProposalCard(
                    proposal: proposal,
                    onAccept: { operationID in Task { await store.accept(operationID: operationID) } },
                    onReject: { operationID in Task { await store.reject(operationID: operationID) } },
                    onAcceptAll: { Task { await store.acceptAll(proposalID: proposal.id) } },
                    onRejectAll: { Task { await store.rejectAll(proposalID: proposal.id) } }
                )
            }
        }
        .padding(.trailing, 28)
        .padding(.bottom, 108)
    }
}

private struct CosmoInlineProposalCard: View {
    let proposal: CosmoAssistantProposal
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    let onAcceptAll: () -> Void
    let onRejectAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundStyle(DS.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.text)
                    Text(proposal.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                if proposal.operations.count > 1 {
                    Button("Reject all", action: onRejectAll)
                        .buttonStyle(.plain)
                    Button("Accept all", action: onAcceptAll)
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.accent)
                }
            }

            ForEach(proposal.operations) { operation in
                CosmoInlineOperationReviewRow(
                    operation: operation,
                    onAccept: { onAccept(operation.id) },
                    onReject: { onReject(operation.id) }
                )
            }
        }
        .padding(14)
        .frame(width: 420)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 16))
        .overlay(.rect(cornerRadius: 16).stroke(DS.borderSubtle, lineWidth: 1))
        .dsFloatingShadow()
    }
}

private struct CosmoInlineOperationReviewRow: View {
    let operation: CosmoAssistantProposalOperation
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(operation.hunks) { hunk in
                    Text(rowText(for: hunk))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(rowColor(for: hunk))
                        .strikethrough(hunk.kind == .removed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if operation.status == .conflicted {
                    Text("Source changed. Regenerate this edit.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.red)
                }
            }
            HStack(spacing: 4) {
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept change")
                Button(action: onReject) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reject change")
            }
        }
        .padding(10)
        .background(DS.surfaceCard, in: .rect(cornerRadius: 10))
    }

    private func rowText(for hunk: CosmoProposalHunk) -> String {
        switch hunk.kind {
        case .context: return "  \(hunk.text)"
        case .removed: return "- \(hunk.text)"
        case .added: return "+ \(hunk.text)"
        }
    }

    private func rowColor(for hunk: CosmoProposalHunk) -> Color {
        switch hunk.kind {
        case .context: return DS.textSecondary
        case .removed: return DS.red
        case .added: return DS.accent
        }
    }
}
```

- [ ] **Step 5: Render overlay in MainView**

In `Navigation/MainView.swift`, add near the assistant bar:

```swift
VStack {
    Spacer()
    HStack {
        Spacer()
        CosmoInlineProposalOverlay(store: inlineAssistantStore)
    }
}
.zIndex(56)
```

- [ ] **Step 6: Re-run route tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add UI/InlineAssistant/CosmoInlineProposalOverlay.swift UI/InlineAssistant/CosmoInlineAssistantStore.swift Navigation/MainView.swift Tests/CosmoOSTests/CosmoInlineAssistantRoutingTests.swift
git commit -m "feat: review inline assistant proposals"
```

## Task 9: Note and Content Editable Surface Providers

**Files:**
- Modify: `UI/FocusMode/Notes/NoteFocusModeView.swift`
- Modify: `UI/FocusMode/Content/ContentFocusModeView.swift`
- Modify: `Editor/TextKitCoordinator.swift`
- Test: `Tests/CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests.swift`

- [ ] **Step 1: Write failing surface provider tests**

Create `Tests/CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoInlineAssistantSurfaceProviderTests: XCTestCase {
    func testLineAnchorsCoverEachNonEmptyLine() {
        let anchors = CosmoTextAnchorBuilder.lineAnchors(for: "A\n\nB")
        XCTAssertEqual(anchors.map(\.id), ["line-0", "line-2"])
        XCTAssertEqual(anchors[0].utf16Start, 0)
        XCTAssertEqual(anchors[0].utf16Length, 1)
        XCTAssertEqual(anchors[1].utf16Start, 3)
        XCTAssertEqual(anchors[1].utf16Length, 1)
    }
}
```

- [ ] **Step 2: Run provider tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests
```

Expected: FAIL because `CosmoTextAnchorBuilder` does not exist.

- [ ] **Step 3: Add text anchor builder**

Add to `UI/InlineAssistant/CosmoEditableSurfaceProvider.swift`:

```swift
enum CosmoTextAnchorBuilder {
    static func lineAnchors(for text: String) -> [CosmoEditableAnchor] {
        let ns = text as NSString
        let lines = text.components(separatedBy: "\n")
        var anchors: [CosmoEditableAnchor] = []
        var location = 0

        for (index, line) in lines.enumerated() {
            let length = (line as NSString).length
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                anchors.append(
                    CosmoEditableAnchor(
                        id: "line-\(index)",
                        label: "Line \(index + 1)",
                        utf16Start: location,
                        utf16Length: length
                    )
                )
            }
            location += length
            if location < ns.length {
                location += 1
            }
        }

        return anchors
    }
}
```

- [ ] **Step 4: Register Note provider**

In `UI/FocusMode/Notes/NoteFocusModeView.swift`, update the existing `NoteContextProvider` to conform to `CosmoEditableSurfaceProvider`:

```swift
@MainActor
class NoteContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    var surfaceID: String { "note:\(atom.uuid)" }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let content = contentRef()
        let targetID = EditorCommandTarget.noteBody(atom.uuid)
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: targetID,
            kind: .text,
            title: resolvedTitle,
            text: content,
            sourceHash: CosmoEditableSurfaceHasher.hash(content),
            anchors: CosmoTextAnchorBuilder.lineAnchors(for: content)
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        try await CosmoWorkspaceEditApplicator.applyTextOperation(operation, snapshot: editableSnapshot())
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected.")
    }
}
```

When the provider is created in `NoteFocusModeView`, add:

```swift
CosmoEditableSurfaceRegistry.shared.register(provider)
```

On disappear, unregister:

```swift
CosmoEditableSurfaceRegistry.shared.unregister(surfaceID: provider.surfaceID)
```

- [ ] **Step 5: Register Content provider**

In `UI/FocusMode/Content/ContentFocusModeView.swift`, update `ContentContextProvider` to conform to `CosmoEditableSurfaceProvider`:

```swift
@MainActor
class ContentContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    var surfaceID: String { "content:\(atom.uuid)" }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let state = stateRef()
        let targetID = "content:\(atom.uuid):draft"
        let draft = state.draftContent
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: targetID,
            kind: .text,
            title: atom.title ?? "Content draft",
            text: draft,
            sourceHash: CosmoEditableSurfaceHasher.hash(draft),
            anchors: CosmoTextAnchorBuilder.lineAnchors(for: draft)
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        try await CosmoWorkspaceEditApplicator.applyTextOperation(operation, snapshot: editableSnapshot())
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected.")
    }
}
```

Register and unregister this provider in the same lifecycle points where `CosmoWindowViewModel.shared.updateContext(provider:)` is called.

- [ ] **Step 6: Implement `replaceRangeInEditor` in TextKitCoordinator**

In `Editor/TextKitCoordinator.swift`, find the existing notification observers for `replaceSelectionInEditor` and `insertTextInEditor`. Add an observer for `.replaceRangeInEditor` that:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleReplaceRangeInEditor(_:)),
    name: .replaceRangeInEditor,
    object: nil
)
```

Add the handler near `handleReplaceSelectionInEditor(_:)`:

```swift
@objc private func handleReplaceRangeInEditor(_ notification: Notification) {
    guard let textView = activeTextView,
          let start = notification.userInfo?["utf16Start"] as? Int,
          let length = notification.userInfo?["utf16Length"] as? Int,
          let replacement = notification.userInfo?["replacementText"] as? String else {
        return
    }
    guard acceptsEditorCommand(notification) else { return }

    let allowInactive = notification.userInfo?["allowInactive"] as? Bool ?? false
    guard allowInactive || textView.window?.firstResponder === textView else { return }

    let range = NSRange(location: start, length: length)
    guard NSMaxRange(range) <= textView.string.utf16.count else { return }
    textView.textStorage?.replaceCharacters(in: range, with: replacement)
    textView.didChangeText()
}
```

- [ ] **Step 7: Re-run provider tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add UI/FocusMode/Notes/NoteFocusModeView.swift UI/FocusMode/Content/ContentFocusModeView.swift Editor/TextKitCoordinator.swift UI/InlineAssistant/CosmoEditableSurfaceProvider.swift Tests/CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests.swift
git commit -m "feat: expose note and content surfaces to inline assistant"
```

## Task 10: Idea Editable Surface Provider

**Files:**
- Modify: `UI/FocusMode/Ideas/IdeaFocusModeView.swift`
- Test: `Tests/CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests.swift`

- [ ] **Step 1: Add idea target test**

Append to `Tests/CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests.swift`:

```swift
func testIdeaTargetsUseStableFieldIDs() {
    XCTAssertEqual(CosmoIdeaEditableTargets.body(atomUUID: "idea-1"), "idea:idea-1:body")
    XCTAssertEqual(CosmoIdeaEditableTargets.hooks(atomUUID: "idea-1"), "idea:idea-1:hooks")
}
```

- [ ] **Step 2: Run provider tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests
```

Expected: FAIL because `CosmoIdeaEditableTargets` does not exist.

- [ ] **Step 3: Add idea target helper**

Add near `IdeaContextProvider` in `UI/FocusMode/Ideas/IdeaFocusModeView.swift`:

```swift
enum CosmoIdeaEditableTargets {
    static func body(atomUUID: String) -> String { "idea:\(atomUUID):body" }
    static func hooks(atomUUID: String) -> String { "idea:\(atomUUID):hooks" }
}
```

- [ ] **Step 4: Make IdeaContextProvider editable**

Update `IdeaContextProvider` to conform to `CosmoEditableSurfaceProvider`:

```swift
@MainActor
class IdeaContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    var surfaceID: String { "idea:\(atom.uuid)" }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let body = viewModel?.editableBody ?? ""
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: CosmoIdeaEditableTargets.body(atomUUID: atom.uuid),
            kind: .text,
            title: atom.title ?? "Idea",
            text: body,
            sourceHash: CosmoEditableSurfaceHasher.hash(body),
            anchors: CosmoTextAnchorBuilder.lineAnchors(for: body)
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard let viewModel else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Idea is no longer active.")
        }
        let snapshot = editableSnapshot()
        guard operation.sourceHash == snapshot.sourceHash,
              let anchorID = operation.anchorID,
              let anchor = snapshot.anchors.first(where: { $0.id == anchorID }),
              let replacement = operation.proposedText else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Source changed.")
        }
        let ns = NSMutableString(string: viewModel.editableBody)
        ns.replaceCharacters(in: NSRange(location: anchor.utf16Start, length: anchor.utf16Length), with: replacement)
        viewModel.editableBody = ns as String
        await viewModel.save()
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied.")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected.")
    }
}
```

Register and unregister the provider in `IdeaFocusModeView` lifecycle.

- [ ] **Step 5: Re-run provider tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add UI/FocusMode/Ideas/IdeaFocusModeView.swift Tests/CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests.swift
git commit -m "feat: expose idea body to inline assistant"
```

## Task 11: Canvas Editable Surface Provider and Proposal Preview

**Files:**
- Modify: `Canvas/CanvasView.swift`
- Modify: `UI/InlineAssistant/CosmoInlineAssistantModels.swift`
- Test: `Tests/CosmoOSTests/CosmoInlineAssistantCanvasProposalTests.swift`

- [ ] **Step 1: Write failing canvas proposal tests**

Create `Tests/CosmoOSTests/CosmoInlineAssistantCanvasProposalTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoInlineAssistantCanvasProposalTests: XCTestCase {
    func testCanvasPayloadEncodesMoveOperation() {
        let operation = CosmoAssistantProposalOperation(
            kind: .canvasPlan,
            targetID: "thinkspace:abc",
            anchorID: "block:block-1",
            originalText: nil,
            proposedText: nil,
            sourceHash: "hash",
            rationale: "Move block into a cleaner column.",
            canvasPayload: [
                "operation": "moveBlock",
                "blockID": "block-1",
                "x": "120",
                "y": "240"
            ]
        )

        XCTAssertEqual(operation.canvasPayload["operation"], "moveBlock")
        XCTAssertEqual(operation.canvasPayload["blockID"], "block-1")
    }
}
```

- [ ] **Step 2: Run canvas proposal tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantCanvasProposalTests
```

Expected: PASS if Task 1 already added `canvasPayload`; otherwise FAIL and add that property from Task 1.

- [ ] **Step 3: Make CanvasContextProvider editable**

In `Canvas/CanvasView.swift`, update `CanvasContextProvider` to conform to `CosmoEditableSurfaceProvider`:

```swift
@MainActor
class CanvasContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    var surfaceID: String { "thinkspace:\(currentThinkspaceId ?? "active")" }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let blocks = spatialEngine?.blocks ?? []
        let blockLines = blocks.map { block in
            "\(block.id)|\(block.entityUuid)|\(block.entityType.rawValue)|\(block.title ?? "")|\(Int(block.position.x)),\(Int(block.position.y))"
        }.joined(separator: "\n")
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: surfaceID,
            kind: .canvas,
            title: currentThinkspaceTitle ?? "Thinkspace",
            text: blockLines,
            sourceHash: CosmoEditableSurfaceHasher.hash(blockLines),
            anchors: blocks.map { block in
                CosmoEditableAnchor(
                    id: "block:\(block.id)",
                    label: block.title ?? block.entityType.rawValue,
                    utf16Start: 0,
                    utf16Length: 0
                )
            }
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard operation.sourceHash == editableSnapshot().sourceHash else {
            return CosmoEditableOperationResult(operationID: operation.id, status: .conflicted, message: "Canvas changed.")
        }
        NotificationCenter.default.post(
            name: CosmoNotification.Canvas.applyInlineAssistantOperation,
            object: nil,
            userInfo: operation.canvasPayload
        )
        return CosmoEditableOperationResult(operationID: operation.id, status: .applied, message: "Applied canvas operation.")
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected.")
    }
}
```

- [ ] **Step 4: Add canvas notification**

In `Core/CosmoNotifications.swift`, add:

```swift
static let applyInlineAssistantOperation = Notification.Name("com.cosmo.canvas.applyInlineAssistantOperation")
```

Place this inside the existing canvas notification namespace.

- [ ] **Step 5: Handle canvas move operation**

In `Canvas/CanvasView.swift`, add `.onReceive` for `CosmoNotification.Canvas.applyInlineAssistantOperation`:

```swift
.onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.applyInlineAssistantOperation)) { notification in
    guard let operation = notification.userInfo?["operation"] as? String else { return }
    switch operation {
    case "moveBlock":
        guard let blockID = notification.userInfo?["blockID"] as? String,
              let xString = notification.userInfo?["x"] as? String,
              let yString = notification.userInfo?["y"] as? String,
              let x = Double(xString),
              let y = Double(yString),
              let index = spatialEngine.blocks.firstIndex(where: { $0.id == blockID }) else {
            return
        }
        spatialEngine.blocks[index].position = CGPoint(x: x, y: y)
        Task { await spatialEngine.saveBlock(spatialEngine.blocks[index]) }
    default:
        break
    }
}
```

- [ ] **Step 6: Register and unregister canvas provider**

When `CanvasContextProvider` is created and passed to `CosmoWindowViewModel.shared.updateContext(provider:)`, also call:

```swift
CosmoEditableSurfaceRegistry.shared.register(provider)
```

On canvas disappear or thinkspace switch, unregister the previous `surfaceID`.

- [ ] **Step 7: Re-run canvas tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantCanvasProposalTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Canvas/CanvasView.swift Core/CosmoNotifications.swift Tests/CosmoOSTests/CosmoInlineAssistantCanvasProposalTests.swift
git commit -m "feat: expose canvas operations to inline assistant"
```

## Task 12: Keyboard Shortcuts and Command A/Option A Migration

**Files:**
- Modify: `Navigation/MainView.swift`
- Modify: `Core/CosmoApp.swift`
- Modify: `Settings/ShortcutsSettingsTab.swift`
- Test: `Tests/CosmoOSTests/CommandKActionRegistryTests.swift`

- [ ] **Step 1: Add shortcut policy test**

Append to an existing shortcut policy test file or create `Tests/CosmoOSTests/CosmoInlineAssistantShortcutTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class CosmoInlineAssistantShortcutTests: XCTestCase {
    func testOptionAIsInlineAssistantShortcut() {
        let shortcut = CosmoInlineAssistantShortcut.defaultShortcut
        XCTAssertEqual(shortcut.key, "a")
        XCTAssertEqual(shortcut.modifiers, [.option])
    }
}
```

- [ ] **Step 2: Run shortcut tests and verify failure**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantShortcutTests
```

Expected: FAIL because shortcut type does not exist.

- [ ] **Step 3: Add shortcut model**

Create `UI/InlineAssistant/CosmoInlineAssistantShortcut.swift`:

```swift
import SwiftUI

struct CosmoInlineAssistantShortcut: Equatable {
    var key: String
    var modifiers: EventModifiers

    static let defaultShortcut = CosmoInlineAssistantShortcut(key: "a", modifiers: [.option])
}
```

- [ ] **Step 4: Register shortcut handling**

In `Navigation/MainView.swift`, extend the existing keyboard monitor so Option-A posts:

```swift
NotificationCenter.default.post(name: CosmoNotification.Navigation.openInlineAssistant, object: nil)
```

Handle the notification:

```swift
.onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.openInlineAssistant)) { _ in
    inlineAssistantStore.focusComposerRequest += 1
}
```

Add `focusComposerRequest` to `CosmoInlineAssistantStore`:

```swift
@Published var focusComposerRequest = 0
```

In `CosmoInlineAssistantBar`, observe `focusComposerRequest` and focus the text field with `@FocusState`.

- [ ] **Step 5: Add Command A migration behavior**

If the current Command A shortcut opens `CosmoWindowPanelController`, leave Command-A intact for one release and add a setting:

```swift
@AppStorage("inlineAssistant.replacesCommandA") private var replacesCommandA = false
```

When `replacesCommandA` is true, Command-A opens inline assistant pane. When false, Command-A keeps current CosmoWindow behavior and Option-A opens inline assistant.

- [ ] **Step 6: Re-run shortcut tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoInlineAssistantShortcutTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Navigation/MainView.swift Core/CosmoApp.swift Settings/ShortcutsSettingsTab.swift UI/InlineAssistant/CosmoInlineAssistantShortcut.swift Tests/CosmoOSTests/CosmoInlineAssistantShortcutTests.swift
git commit -m "feat: wire inline assistant shortcut"
```

## Task 13: Project Membership and Build Integration

**Files:**
- Modify: `project.yml`
- Modify: `CosmoOS.xcodeproj/project.pbxproj`
- Create: `add_inline_assistant_files.rb`

- [ ] **Step 1: Verify project generation path**

Run:

```bash
which xcodegen || true
```

Expected: If `xcodegen` exists, use `project.yml` and regenerate. If it does not exist, use the file-add script in Step 3.

- [ ] **Step 2: Confirm `project.yml` already includes the `UI` directory**

Run:

```bash
rg -n "sources:|UI" project.yml
```

Expected: `UI` appears under `targets.CosmoOS.sources`, so new `UI/InlineAssistant` files are included when regenerating.

- [ ] **Step 3: Add files to Xcode project if not regenerating**

Create `add_inline_assistant_files.rb`:

```ruby
#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('CosmoOS.xcodeproj')
target = project.targets.find { |t| t.name == 'CosmoOS' }
raise 'Missing CosmoOS target' unless target

ui_group = project.main_group.children.find { |g| g.display_name == 'UI' } || project.main_group.new_group('UI', 'UI')
assistant_group = ui_group.children.find { |g| g.display_name == 'InlineAssistant' } || ui_group.new_group('InlineAssistant', 'UI/InlineAssistant')

files = [
  'UI/InlineAssistant/CosmoInlineAssistantModels.swift',
  'UI/InlineAssistant/CosmoInlineAssistantDiffEngine.swift',
  'UI/InlineAssistant/CosmoEditableSurfaceProvider.swift',
  'UI/InlineAssistant/CosmoEditableSurfaceRegistry.swift',
  'UI/InlineAssistant/CosmoInlineAssistantStore.swift',
  'UI/InlineAssistant/CosmoInlineAssistantAgentBridge.swift',
  'UI/InlineAssistant/CosmoInlineAssistantBar.swift',
  'UI/InlineAssistant/CosmoInlineAssistantPaneView.swift',
  'UI/InlineAssistant/CosmoInlineProposalOverlay.swift',
  'UI/InlineAssistant/CosmoWorkspaceEditApplicator.swift',
  'UI/InlineAssistant/CosmoInlineAssistantShortcut.swift'
]

files.each do |path|
  next unless File.exist?(path)
  name = File.basename(path)
  existing = assistant_group.files.find { |file| file.path&.end_with?(name) }
  next if existing
  ref = assistant_group.new_file(path)
  target.source_build_phase.add_file_reference(ref)
  puts "Added #{path}"
end

project.save
puts 'Saved CosmoOS.xcodeproj'
```

Run:

```bash
ruby add_inline_assistant_files.rb
```

Expected: Prints each new file once and saves the project.

- [ ] **Step 4: Add new test files to test target if the project requires explicit test membership**

If focused test builds report that new test files are not discovered, extend `add_inline_assistant_files.rb` to add files under `Tests/CosmoOSTests` to the `CosmoOSTests` target source phase.

- [ ] **Step 5: Run a full build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

Expected: PASS with exit code 0.

- [ ] **Step 6: Commit**

```bash
git add project.yml CosmoOS.xcodeproj/project.pbxproj add_inline_assistant_files.rb
git commit -m "chore: include inline assistant files in project"
```

## Task 14: End-to-End Verification

**Files:**
- Verify all files changed by Tasks 1-13.

- [ ] **Step 1: Run focused inline assistant tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test \
  -only-testing:CosmoOSTests/CosmoInlineAssistantModelsTests \
  -only-testing:CosmoOSTests/CosmoEditableSurfaceRegistryTests \
  -only-testing:CosmoOSTests/CosmoInlineAssistantToolTests \
  -only-testing:CosmoOSTests/CosmoInlineAssistantRoutingTests \
  -only-testing:CosmoOSTests/CosmoWorkspaceEditApplicatorTests \
  -only-testing:CosmoOSTests/CosmoInlineAssistantSurfaceProviderTests \
  -only-testing:CosmoOSTests/CosmoInlineAssistantCanvasProposalTests \
  -only-testing:CosmoOSTests/PaneManagerInlineAssistantPaneTests \
  -only-testing:CosmoOSTests/CosmoInlineAssistantShortcutTests
```

Expected: PASS.

- [ ] **Step 2: Run related regression tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test \
  -only-testing:CosmoOSTests/CosmoWindowContextSessionTests \
  -only-testing:CosmoOSTests/PaneManagerBrowserPaneTests \
  -only-testing:CosmoOSTests/CommandKActionRegistryTests \
  -only-testing:CosmoOSTests/NotePersistenceRegressionTests \
  -only-testing:CosmoOSTests/ContentFocusPersistenceRegressionTests
```

Expected: PASS.

- [ ] **Step 3: Manually verify action mode on a note**

Run the app and open a note focus mode. Press Option-A and submit:

```text
Replace the rent line with Rent: $5,000/mo
```

Expected:
- The assistant bar shows processing status.
- The right pane does not open.
- A proposal card appears with old rent removed and new rent added.
- Accept applies only that line.
- Reject leaves the note unchanged.

- [ ] **Step 4: Manually verify answer mode**

Press Option-A and submit:

```text
What is the strongest hook in this draft?
```

Expected:
- The assistant pane opens.
- The user prompt appears.
- The assistant answer appears in the pane.
- No proposal card appears.

- [ ] **Step 5: Manually verify canvas action mode**

Open a thinkspace with at least three blocks. Press Option-A and submit:

```text
Organize this canvas into a cleaner left-to-right flow
```

Expected:
- The assistant stages canvas operations.
- Each operation has accept and reject controls.
- Accepting a move changes only the targeted block.
- Rejecting a move leaves that block in place.

- [ ] **Step 6: Check changed files**

Run:

```bash
git status --short
```

Expected: Only files from this implementation are changed, plus existing user changes that were present before this work.

- [ ] **Step 7: Commit final integration**

```bash
git add UI/InlineAssistant Agent/Core Agent/Models Core Navigation Editor UI/FocusMode Canvas Tests/CosmoOSTests project.yml CosmoOS.xcodeproj/project.pbxproj add_inline_assistant_files.rb
git commit -m "feat: add inline assistant with reviewed diffs"
```

## Self-Review Checklist

- Spec coverage: The plan covers bottom composer, pane mode, answer-vs-action routing, model/tool reuse, review-first edits, per-operation accept/reject, note/content/idea/canvas surfaces, and shortcut migration.
- Placeholder scan: No task depends on an unnamed file or unspecified component. Every new model, callback, and core test has a concrete name.
- Type consistency: `CosmoAssistantProposal`, `CosmoAssistantProposalOperation`, `CosmoEditableSourceSnapshot`, `CosmoEditableSurfaceProvider`, and `CosmoInlineAssistantStore` use the same names across tests and implementation steps.
- Risk: The `TextKitCoordinator` range replacement handler depends on `activeTextView`, `acceptsEditorCommand(_:)`, and `didChangeText()`, which are already used in the coordinator. Verify with a focused build immediately after Task 9.
- Risk: Adding `.workspaceEditing` requires updating every `AgentToolBundle` switch in `UI/CosmoWindow/CollaboratorModels.swift` and `Agent/Core/AgentToolRegistry.swift`; missing one switch branch will surface as a compiler error.
- Risk: Canvas movement applies through `spatialEngine.saveBlock(_:)`; if future changes add batching, keep single-block accept/reject behavior intact.
