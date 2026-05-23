# Note To Thinkspace Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Canvas Organizer agent so a user can say “take this long note and put every major concept into its own cluster in this thinkspace,” and Cosmo creates structured clusters and one note block per module without changing a single source word. The original long note remains visible by default until the system has proven itself.

**Architecture:** Use a two-phase plan/apply flow. The model proposes structure, labels, placement, and source ranges only. The app validates the current note body hash, extracts exact text locally from those ranges, shows a visible review card, then applies the plan by creating note atoms, canvas blocks, and cluster metadata in the target thinkspace. The model never supplies rewritten module body text for the final write path.

**Tech Stack:** Swift, SwiftUI, GRDB-backed repository services, `AtomRepository`, `CanvasBlockRecord`, `ThinkspaceMetadata`, existing Cosmo agent tool registry/executor, Canvas Organizer custom agent profile.

---

## File Map

Create:

- `AI/NoteStructurePlanModels.swift` - exact-copy source snapshot, pending plan, validation, hash, and range extraction.
- `AI/NoteStructureApplyService.swift` - applies validated note-structure plans to atoms, canvas blocks, clusters, and thinkspace metadata.
- `Tests/CosmoOSTests/NoteStructurePlanTests.swift` - focused tests for exact copying, validation, tool parsing, and apply behavior.

Modify:

- `Agent/Core/AgentToolRegistry.swift` - add `propose_note_structure_plan` to the canvas spatial tool bundle.
- `Agent/Core/AgentToolExecutor.swift` - parse and emit pending note structure plans.
- `UI/CosmoWindow/CosmoWindowViewModel.swift` - hold pending plan state, wire tool callbacks, build source snapshots, apply/cancel/revise plans.
- `UI/CosmoWindow/CosmoWindowView.swift` - show visible review UI for the proposed clusters/modules.
- `UI/CosmoWindow/CollaboratorModels.swift` - upgrade Canvas Organizer prompt and seed prompts.
- `CosmoOS.xcodeproj/project.pbxproj` - add new Swift files to the app and test targets if the project does not use synchronized groups for these paths.

Reference during implementation:

- `AI/CanvasProjectionApplyService.swift` - reuse its patterns for creating atoms, canvas blocks, and cluster metadata.
- `Canvas/CanvasBlock.swift` - use `CanvasBlock.fromAtom(_:position:)` and the document block sizing conventions.
- `Canvas/CanvasCluster.swift` - use existing `CanvasCluster` / `CodableCluster` metadata shape.
- `Data/Models/CanvasBlockRecord.swift` - persist created blocks through `CanvasBlockRecord.from`.
- `UI/CosmoWindow/CollaboratorModels.swift` - current `PendingCanvasPlan`, Canvas Organizer profile, and seed prompts.

## Behavioral Contract

- The source note body is never edited by this feature.
- `keepOriginalVisible` defaults to `true` and the UI keeps that state visible in the review card.
- New module notes must contain text copied exactly from the source note, including punctuation, casing, whitespace, markdown, and line breaks.
- The model proposes UTF-16 source ranges, not replacement text.
- The app verifies the source note hash immediately before preview and again immediately before apply.
- If the source note changed after the plan was generated, Apply is disabled and the user is asked to regenerate the plan.
- The Canvas Organizer remains the agent for this workflow; add capability to it instead of creating a separate agent for the first version.
- When the user says “inside this thinkspace,” use the active thinkspace. When the user says “inside the thinkspace this block is already in,” resolve the note block’s current thinkspace. If neither can be resolved, Cosmo should ask for the target thinkspace before proposing the plan.

## Task 1: Add Exact-Copy Plan Models

- [ ] Create `AI/NoteStructurePlanModels.swift`.
- [ ] Add model types:

```swift
import CryptoKit
import Foundation

struct NoteStructureSourceSnapshot: Equatable {
    let sourceNoteUUID: UUID
    let sourceTitle: String
    let body: String
    let bodyHash: String

    init(sourceNoteUUID: UUID, sourceTitle: String, body: String) {
        self.sourceNoteUUID = sourceNoteUUID
        self.sourceTitle = sourceTitle
        self.body = body
        self.bodyHash = Self.hashBody(body)
    }

    static func hashBody(_ body: String) -> String {
        let digest = SHA256.hash(data: Data(body.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct PendingNoteStructurePlan: Identifiable, Equatable {
    let id: UUID
    let title: String
    let rationale: String
    let sourceNoteUUID: UUID
    let sourceTitle: String
    let sourceBodyHash: String
    let targetThinkspaceUUID: UUID
    let keepOriginalVisible: Bool
    let clusters: [NoteStructureClusterProposal]
    let modules: [NoteStructureModuleProposal]
    let createdAt: Date
}

struct NoteStructureClusterProposal: Identifiable, Equatable {
    let id: UUID
    let name: String
    let colorIndex: Int
    let frame: CGRect
    let moduleIDs: [UUID]
}

struct NoteStructureModuleProposal: Identifiable, Equatable {
    let id: UUID
    let clusterID: UUID
    let title: String
    let startUTF16Offset: Int
    let lengthUTF16: Int
    let position: CGPoint
    let size: CGSize

    func copiedText(in body: String) throws -> String {
        let nsBody = body as NSString
        let range = NSRange(location: startUTF16Offset, length: lengthUTF16)
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= nsBody.length else {
            throw NoteStructurePlanError.invalidRange(moduleID: id)
        }
        let text = nsBody.substring(with: range)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw NoteStructurePlanError.emptyModuleText(moduleID: id)
        }
        return text
    }
}

enum NoteStructurePlanError: Error, Equatable {
    case sourceHashMismatch(expected: String, actual: String)
    case invalidRange(moduleID: UUID)
    case emptyModuleText(moduleID: UUID)
    case missingCluster(moduleID: UUID, clusterID: UUID)
    case missingModule(clusterID: UUID, moduleID: UUID)
}
```

- [ ] Add `PendingNoteStructurePlan.validate(against snapshot:) throws`:

```swift
extension PendingNoteStructurePlan {
    func validate(against snapshot: NoteStructureSourceSnapshot) throws {
        guard sourceBodyHash == snapshot.bodyHash else {
            throw NoteStructurePlanError.sourceHashMismatch(expected: sourceBodyHash, actual: snapshot.bodyHash)
        }

        let clustersByID = Dictionary(uniqueKeysWithValues: clusters.map { ($0.id, $0) })
        let modulesByID = Dictionary(uniqueKeysWithValues: modules.map { ($0.id, $0) })

        for module in modules {
            guard clustersByID[module.clusterID] != nil else {
                throw NoteStructurePlanError.missingCluster(moduleID: module.id, clusterID: module.clusterID)
            }
            _ = try module.copiedText(in: snapshot.body)
        }

        for cluster in clusters {
            for moduleID in cluster.moduleIDs {
                guard modulesByID[moduleID] != nil else {
                    throw NoteStructurePlanError.missingModule(clusterID: cluster.id, moduleID: moduleID)
                }
            }
        }
    }
}
```

- [ ] Add focused tests in `Tests/CosmoOSTests/NoteStructurePlanTests.swift`:

```swift
func testModuleExtractsExactTextFromUTF16Range() throws {
    let body = "Intro\n\nModule one 💡\nLine two.\n\nModule two"
    let nsBody = body as NSString
    let exact = "Module one 💡\nLine two."
    let range = nsBody.range(of: exact)

    let module = NoteStructureModuleProposal(
        id: UUID(),
        clusterID: UUID(),
        title: "Module one",
        startUTF16Offset: range.location,
        lengthUTF16: range.length,
        position: CGPoint(x: 100, y: 100),
        size: CanvasBlock.documentLayoutSize
    )

    XCTAssertEqual(try module.copiedText(in: body), exact)
}
```

```swift
func testPlanValidationFailsWhenSourceHashChanges() throws {
    let noteID = UUID()
    let targetID = UUID()
    let snapshot = NoteStructureSourceSnapshot(sourceNoteUUID: noteID, sourceTitle: "Plan", body: "One\n\nTwo")
    let changed = NoteStructureSourceSnapshot(sourceNoteUUID: noteID, sourceTitle: "Plan", body: "One\n\nTwo\n\nThree")

    let clusterID = UUID()
    let moduleID = UUID()
    let plan = PendingNoteStructurePlan(
        id: UUID(),
        title: "Structure note",
        rationale: "Split major concepts.",
        sourceNoteUUID: noteID,
        sourceTitle: "Plan",
        sourceBodyHash: snapshot.bodyHash,
        targetThinkspaceUUID: targetID,
        keepOriginalVisible: true,
        clusters: [NoteStructureClusterProposal(id: clusterID, name: "Core", colorIndex: 0, frame: CGRect(x: 0, y: 0, width: 900, height: 700), moduleIDs: [moduleID])],
        modules: [NoteStructureModuleProposal(id: moduleID, clusterID: clusterID, title: "One", startUTF16Offset: 0, lengthUTF16: 3, position: CGPoint(x: 80, y: 80), size: CanvasBlock.documentLayoutSize)],
        createdAt: Date()
    )

    XCTAssertThrowsError(try plan.validate(against: changed)) { error in
        guard case NoteStructurePlanError.sourceHashMismatch = error else {
            return XCTFail("Expected sourceHashMismatch")
        }
    }
}
```

```swift
func testOriginalNoteRemainsVisibleByDefault() throws {
    let snapshot = NoteStructureSourceSnapshot(sourceNoteUUID: UUID(), sourceTitle: "Long note", body: "A module")
    let clusterID = UUID()
    let moduleID = UUID()
    let plan = PendingNoteStructurePlan(
        id: UUID(),
        title: "Structure note",
        rationale: "Create clusters.",
        sourceNoteUUID: snapshot.sourceNoteUUID,
        sourceTitle: snapshot.sourceTitle,
        sourceBodyHash: snapshot.bodyHash,
        targetThinkspaceUUID: UUID(),
        keepOriginalVisible: true,
        clusters: [NoteStructureClusterProposal(id: clusterID, name: "A", colorIndex: 0, frame: CGRect(x: 0, y: 0, width: 900, height: 700), moduleIDs: [moduleID])],
        modules: [NoteStructureModuleProposal(id: moduleID, clusterID: clusterID, title: "A module", startUTF16Offset: 0, lengthUTF16: 8, position: CGPoint(x: 80, y: 80), size: CanvasBlock.documentLayoutSize)],
        createdAt: Date()
    )

    XCTAssertTrue(plan.keepOriginalVisible)
    XCTAssertNoThrow(try plan.validate(against: snapshot))
}
```

- [ ] Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/NoteStructurePlanTests
```

- [ ] Commit:

```bash
git add AI/NoteStructurePlanModels.swift Tests/CosmoOSTests/NoteStructurePlanTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: add exact note structure plan models"
```

## Task 2: Add Canvas Organizer Tool Schema And Parser

- [ ] In `Agent/Core/AgentToolRegistry.swift`, add a new tool to `canvasSpatialTools` named `propose_note_structure_plan`.
- [ ] The schema must describe that `modules` contain source ranges, not generated text:

```swift
AgentToolDefinition(
    name: "propose_note_structure_plan",
    description: "Propose a reviewable plan to split the active source note into exact-copy module notes inside clusters. Do not provide rewritten module bodies; provide UTF-16 source ranges only.",
    parameters: [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "rationale": ["type": "string"],
            "sourceNoteUUID": ["type": "string"],
            "sourceTitle": ["type": "string"],
            "sourceBodyHash": ["type": "string"],
            "targetThinkspaceUUID": ["type": "string"],
            "keepOriginalVisible": ["type": "boolean"],
            "clusters": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "name": ["type": "string"],
                        "colorIndex": ["type": "integer"],
                        "x": ["type": "number"],
                        "y": ["type": "number"],
                        "width": ["type": "number"],
                        "height": ["type": "number"],
                        "moduleIDs": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["id", "name", "colorIndex", "x", "y", "width", "height", "moduleIDs"]
                ]
            ],
            "modules": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "clusterID": ["type": "string"],
                        "title": ["type": "string"],
                        "startUTF16Offset": ["type": "integer"],
                        "lengthUTF16": ["type": "integer"],
                        "x": ["type": "number"],
                        "y": ["type": "number"],
                        "width": ["type": "number"],
                        "height": ["type": "number"]
                    ],
                    "required": ["id", "clusterID", "title", "startUTF16Offset", "lengthUTF16", "x", "y"]
                ]
            ]
        ],
        "required": ["title", "rationale", "sourceNoteUUID", "sourceTitle", "sourceBodyHash", "targetThinkspaceUUID", "clusters", "modules"]
    ]
)
```

- [ ] In `Agent/Core/AgentToolExecutor.swift`, add:

```swift
var onNoteStructurePlan: ((PendingNoteStructurePlan) -> Void)?
```

- [ ] Add a switch case for `propose_note_structure_plan`.
- [ ] Add `private func proposeNoteStructurePlan(_ arguments: [String: Any]) async throws -> String`.
- [ ] Parser requirements:
  - Parse UUID strings strictly with `UUID(uuidString:)`.
  - Default `keepOriginalVisible` to `true` when omitted.
  - Default module size to `CanvasBlock.documentLayoutSize` when width or height are omitted.
  - Reject empty `clusters` and empty `modules`.
  - Construct `PendingNoteStructurePlan` and call `onNoteStructurePlan?(plan)` on the main actor.
  - Return a short success string such as `"Proposed note structure plan for review."`

- [ ] Add tests:

```swift
func testCanvasSpatialToolsIncludeNoteStructurePlan() {
    let tools = AgentToolRegistry.toolDefinitions(for: [.canvasSpatial])
    XCTAssertTrue(tools.contains { $0.name == "propose_note_structure_plan" })
}
```

```swift
func testExecutorParsesNoteStructurePlanAndKeepsOriginalVisibleByDefault() async throws {
    let executor = AgentToolExecutor()
    let expectation = XCTestExpectation(description: "Plan callback")
    var received: PendingNoteStructurePlan?
    executor.onNoteStructurePlan = { plan in
        received = plan
        expectation.fulfill()
    }

    let sourceID = UUID()
    let targetID = UUID()
    let clusterID = UUID()
    let moduleID = UUID()

    _ = try await executor.execute(
        toolName: "propose_note_structure_plan",
        arguments: [
            "title": "Structure note",
            "rationale": "Split concepts.",
            "sourceNoteUUID": sourceID.uuidString,
            "sourceTitle": "Long note",
            "sourceBodyHash": "abc123",
            "targetThinkspaceUUID": targetID.uuidString,
            "clusters": [[
                "id": clusterID.uuidString,
                "name": "Core",
                "colorIndex": 1,
                "x": 0,
                "y": 0,
                "width": 900,
                "height": 700,
                "moduleIDs": [moduleID.uuidString]
            ]],
            "modules": [[
                "id": moduleID.uuidString,
                "clusterID": clusterID.uuidString,
                "title": "Module",
                "startUTF16Offset": 0,
                "lengthUTF16": 10,
                "x": 80,
                "y": 80
            ]]
        ]
    )

    await fulfillment(of: [expectation], timeout: 1)
    XCTAssertEqual(received?.sourceNoteUUID, sourceID)
    XCTAssertEqual(received?.targetThinkspaceUUID, targetID)
    XCTAssertEqual(received?.keepOriginalVisible, true)
}
```

- [ ] Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/NoteStructurePlanTests
```

- [ ] Commit:

```bash
git add Agent/Core/AgentToolRegistry.swift Agent/Core/AgentToolExecutor.swift Tests/CosmoOSTests/NoteStructurePlanTests.swift
git commit -m "feat: let canvas organizer propose note structure plans"
```

## Task 3: Build Active Note Source Snapshot And Target Thinkspace Resolution

- [ ] In `UI/CosmoWindow/CosmoWindowViewModel.swift`, add a helper that returns a source snapshot for the active note:

```swift
@MainActor
func activeNoteStructureSnapshot() -> NoteStructureSourceSnapshot? {
    guard let context = currentContext,
          context.type == .note,
          let noteUUID = context.entityUUID,
          let body = context.noteBody else {
        return nil
    }

    return NoteStructureSourceSnapshot(
        sourceNoteUUID: noteUUID,
        sourceTitle: context.displayTitle,
        body: body
    )
}
```

- [ ] If the current context type does not already expose `noteBody`, add it through the existing note context provider rather than scraping visible UI text.
- [ ] Add a target thinkspace resolver:

```swift
@MainActor
func resolvedTargetThinkspaceForNoteStructure() -> UUID? {
    if let activeThinkspaceUUID {
        return activeThinkspaceUUID
    }

    if let activeNoteUUID = currentContext?.entityUUID {
        return repository.findPrimaryThinkspaceContainingCanvasBlock(atomUUID: activeNoteUUID)
    }

    return nil
}
```

- [ ] Implement `findPrimaryThinkspaceContainingCanvasBlock(atomUUID:)` using `canvas_blocks` rows where `atom_uuid` or `entity_uuid` matches the source note. Prefer the currently visible thinkspace if multiple rows exist.
- [ ] When building the system/user context for Canvas Organizer, include:

```text
Active source note for structure planning:
- sourceNoteUUID: <uuid>
- sourceTitle: <title>
- sourceBodyHash: <hash>
- targetThinkspaceUUID: <uuid>
- keepOriginalVisible: true
- Body is available in context. Use UTF-16 ranges into this exact body.
```

- [ ] Add note-structure intent words to the routing heuristic that forces `.canvasSpatial`:
  - `split note`
  - `structure note`
  - `major concept`
  - `module`
  - `cluster`
  - `thinkspace`
- [ ] If no target thinkspace can be resolved, the assistant must ask the user which thinkspace to use instead of hallucinating a destination.
- [ ] Add tests:
  - A note with body `A\n\nB` produces a snapshot whose hash equals `NoteStructureSourceSnapshot.hashBody`.
  - A request containing `split this note into clusters` selects the Canvas Organizer-capable tool bundle.
  - When no target thinkspace exists, the context builder surfaces a missing-target state instead of inventing a UUID.

- [ ] Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowContextSessionTests -only-testing:CosmoOSTests/NoteStructurePlanTests
```

- [ ] Commit:

```bash
git add UI/CosmoWindow/CosmoWindowViewModel.swift Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift Tests/CosmoOSTests/NoteStructurePlanTests.swift
git commit -m "feat: provide active note snapshots for structure planning"
```

## Task 4: Add Visible Pending Plan Review UI

- [ ] In `UI/CosmoWindow/CosmoWindowViewModel.swift`, add:

```swift
@Published var pendingNoteStructurePlan: PendingNoteStructurePlan?
@Published var pendingNoteStructurePreviewError: NoteStructurePlanError?
```

- [ ] Wire the executor callback:

```swift
toolExecutor.onNoteStructurePlan = { [weak self] plan in
    Task { @MainActor in
        self?.receivePendingNoteStructurePlan(plan)
    }
}
```

- [ ] Add view model methods:

```swift
@MainActor
func receivePendingNoteStructurePlan(_ plan: PendingNoteStructurePlan) {
    guard let snapshot = activeNoteStructureSnapshot() else {
        pendingNoteStructurePreviewError = .sourceHashMismatch(expected: plan.sourceBodyHash, actual: "")
        pendingNoteStructurePlan = plan
        return
    }

    do {
        try plan.validate(against: snapshot)
        pendingNoteStructurePreviewError = nil
    } catch let error as NoteStructurePlanError {
        pendingNoteStructurePreviewError = error
    } catch {
        pendingNoteStructurePreviewError = .sourceHashMismatch(expected: plan.sourceBodyHash, actual: snapshot.bodyHash)
    }

    pendingNoteStructurePlan = plan
}

@MainActor
func cancelPendingNoteStructurePlan() {
    pendingNoteStructurePlan = nil
    pendingNoteStructurePreviewError = nil
}

@MainActor
func requestRevisionForPendingNoteStructurePlan() {
    guard let plan = pendingNoteStructurePlan else { return }
    sendUserMessage("Revise the note structure plan named \(plan.title). Keep the original note visible and keep exact source ranges only.")
}
```

- [ ] Add `applyPendingNoteStructurePlan()` in Task 5 after the apply service exists.
- [ ] In `UI/CosmoWindow/CosmoWindowView.swift`, add a review card that appears by default when `pendingNoteStructurePlan` exists.
- [ ] Review card content:
  - Header: plan title.
  - Source note title.
  - Target thinkspace identifier or resolved display name.
  - Badge: `Original stays visible`.
  - Cluster list with module counts.
  - Module rows showing title and app-extracted text preview.
  - Apply button disabled when `pendingNoteStructurePreviewError != nil`.
  - Revise and Cancel controls.
- [ ] Keep the UI dense and operational. This is a tool surface inside Cosmo, not a marketing card.
- [ ] Use the same visual language as existing pending canvas plan cards and insertion cards from the collaborator UI. If the current card style uses bordered rounded groups, reuse those components rather than inventing a new style.
- [ ] Add a hash mismatch state:

```text
The source note changed after this plan was created. Regenerate the plan before applying it.
```

- [ ] Add tests where feasible at the view-model layer:
  - Valid plan clears preview error.
  - Hash mismatch sets preview error and disables apply.
  - Cancel clears the pending plan.

- [ ] Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowContextSessionTests -only-testing:CosmoOSTests/NoteStructurePlanTests
```

- [ ] Commit:

```bash
git add UI/CosmoWindow/CosmoWindowViewModel.swift UI/CosmoWindow/CosmoWindowView.swift Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift Tests/CosmoOSTests/NoteStructurePlanTests.swift
git commit -m "feat: show note structure plans before applying"
```

## Task 5: Apply Plan To Atoms, Blocks, And Clusters

- [ ] Create `AI/NoteStructureApplyService.swift`.
- [ ] Public API:

```swift
struct NoteStructureApplyResult: Equatable {
    let operationsApplied: Int
    let clustersCreated: Int
    let notesCreated: Int
    let blocksCreated: Int
    let sourceKeptVisible: Bool
}

final class NoteStructureApplyService {
    static let shared = NoteStructureApplyService()

    func apply(_ plan: PendingNoteStructurePlan) async throws -> NoteStructureApplyResult {
        // Implementation uses the shared repository/database dependencies used by CanvasProjectionApplyService.
    }
}
```

- [ ] Implementation sequence:
  - Fetch the source note atom by `plan.sourceNoteUUID`.
  - Build a fresh `NoteStructureSourceSnapshot` from the current atom body.
  - Run `try plan.validate(against: snapshot)` immediately before writing.
  - Load the target thinkspace atom by `plan.targetThinkspaceUUID`.
  - Decode or initialize `ThinkspaceMetadata` for the target thinkspace.
  - For each `NoteStructureClusterProposal`, create a `CodableCluster` with the proposal name, color, frame, and empty `blockUUIDs`.
  - For each `NoteStructureModuleProposal`, extract exact text locally with `try module.copiedText(in: snapshot.body)`.
  - Create a new `.note` atom using the extracted text as the body.
  - Preserve source provenance in metadata if the atom model supports it. At minimum, link the new note back to the source note through existing link/home metadata patterns.
  - Create a `CanvasBlock` from the new atom at the proposed position.
  - Persist a `CanvasBlockRecord` for the target thinkspace.
  - Append the new note atom UUID to the owning cluster’s `blockUUIDs`.
  - Append the new canvas block ID to the target thinkspace metadata’s block list if that is how the current canvas loader discovers blocks.
  - Save updated `ThinkspaceMetadata`.
  - Leave the source atom body and any existing source canvas block untouched.

- [ ] Use `AI/CanvasProjectionApplyService.swift` as the implementation reference for:
  - repository access
  - `CanvasBlockRecord` persistence
  - metadata load/save
  - duplicate block avoidance where applicable
  - cluster upsert conventions

- [ ] Add tests:
  - Applying a plan creates one note atom per module.
  - Each created note body exactly equals the source substring.
  - Source note body is unchanged after apply.
  - Created canvas blocks are saved against `targetThinkspaceUUID`.
  - Created clusters contain the created note atom UUIDs.
  - A changed source hash prevents all writes.

- [ ] Add `applyPendingNoteStructurePlan()` to `CosmoWindowViewModel`:

```swift
@MainActor
func applyPendingNoteStructurePlan() {
    guard let plan = pendingNoteStructurePlan else { return }

    Task {
        do {
            let result = try await NoteStructureApplyService.shared.apply(plan)
            await MainActor.run {
                self.pendingNoteStructurePlan = nil
                self.pendingNoteStructurePreviewError = nil
                self.appendSystemStatus("Created \(result.notesCreated) exact-copy notes across \(result.clustersCreated) clusters. Original note stayed visible.")
            }
        } catch let error as NoteStructurePlanError {
            await MainActor.run {
                self.pendingNoteStructurePreviewError = error
            }
        } catch {
            await MainActor.run {
                self.appendSystemStatus("Could not apply the note structure plan: \(error.localizedDescription)")
            }
        }
    }
}
```

- [ ] Wire the review card Apply button to `applyPendingNoteStructurePlan()`.
- [ ] Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/NoteStructurePlanTests
```

- [ ] Commit:

```bash
git add AI/NoteStructureApplyService.swift UI/CosmoWindow/CosmoWindowViewModel.swift UI/CosmoWindow/CosmoWindowView.swift Tests/CosmoOSTests/NoteStructurePlanTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: apply exact note structure plans to canvas"
```

## Task 6: Upgrade Canvas Organizer Prompt

- [ ] In `UI/CosmoWindow/CollaboratorModels.swift`, update the `canvas-organizer` runtime prompt.
- [ ] Add this behavior to the prompt:

```text
When the user asks to split, structure, cluster, modularize, or organize a long note into a thinkspace:
- Use inspect_current_thinkspace first when spatial context is needed.
- Use propose_note_structure_plan for the final proposal.
- Do not rewrite, summarize, compress, improve, or paraphrase module bodies.
- Propose UTF-16 source ranges into the active source note body.
- Titles and cluster names may be concise labels, but module body content must be copied by the app from the source ranges.
- Keep the original source note visible by default. Only hide or archive it if the user explicitly asks.
- If the target thinkspace cannot be resolved, ask which thinkspace to use before proposing.
```

- [ ] Add a Canvas Organizer seed prompt:

```swift
"Split this note into structured clusters"
```

- [ ] Add tests:

```swift
func testCanvasOrganizerPromptMentionsNoteStructurePlanTool() {
    let profile = CustomAgentProfile.builtInProfiles.first { $0.id == "canvas-organizer" }
    XCTAssertTrue(profile?.runtimePrompt.contains("propose_note_structure_plan") == true)
    XCTAssertTrue(profile?.runtimePrompt.contains("Keep the original source note visible by default") == true)
}
```

```swift
func testCanvasOrganizerSeedPromptsIncludeSplitNoteWorkflow() {
    let profile = CustomAgentProfile.builtInProfiles.first { $0.id == "canvas-organizer" }
    XCTAssertTrue(profile?.seedPrompts.contains("Split this note into structured clusters") == true)
}
```

- [ ] Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/CosmoWindowContextSessionTests -only-testing:CosmoOSTests/NoteStructurePlanTests
```

- [ ] Commit:

```bash
git add UI/CosmoWindow/CollaboratorModels.swift Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift Tests/CosmoOSTests/NoteStructurePlanTests.swift
git commit -m "feat: teach canvas organizer exact note structuring"
```

## Task 7: Manual Verification In The Mac App

- [ ] Build the app:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

- [ ] Launch the app using the local macOS workflow already used in this repo.
- [ ] Create or open a long note with clearly separated modules:

```text
# Personal Brand Plan

## Voice
Exact wording one.

## Content Pillars
Exact wording two.

## Posting System
Exact wording three.
```

- [ ] Ask Canvas Organizer:

```text
Take this note and put every major concept into its own cluster inside this thinkspace. Make each module its own note block. Do not change a single word. Keep the original note visible.
```

- [ ] Confirm the review card appears and is visible by default.
- [ ] Confirm the card says the original note stays visible.
- [ ] Confirm each module preview matches exact source text.
- [ ] Click Apply.
- [ ] Confirm:
  - The original long note remains on the canvas.
  - New note blocks appear in the target thinkspace.
  - Blocks are grouped into clusters.
  - New note contents match source substrings exactly.
  - No duplicated or missing module text.

- [ ] Change the source note after the review card is generated, then try Apply.
- [ ] Confirm Apply is blocked and the UI asks to regenerate the plan.

## Task 8: Final Verification And Integration

- [ ] Run focused tests:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/NoteStructurePlanTests -only-testing:CosmoOSTests/CosmoWindowContextSessionTests
```

- [ ] Run a full build:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build
```

- [ ] Check formatting and patch health:

```bash
git diff --check
```

- [ ] Inspect final status:

```bash
git status --short
```

- [ ] Final commit if any verification adjustments were needed:

```bash
git add AI/NoteStructurePlanModels.swift AI/NoteStructureApplyService.swift Agent/Core/AgentToolRegistry.swift Agent/Core/AgentToolExecutor.swift UI/CosmoWindow/CosmoWindowViewModel.swift UI/CosmoWindow/CosmoWindowView.swift UI/CosmoWindow/CollaboratorModels.swift Tests/CosmoOSTests/NoteStructurePlanTests.swift Tests/CosmoOSTests/CosmoWindowContextSessionTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: structure long notes into exact canvas clusters"
```

## Risk Controls

- Range accuracy: Use UTF-16 offsets because that matches `NSString` and avoids Swift `String.Index` ambiguity with emoji and composed characters.
- Data loss: The source note is never edited, and apply validates hash before writing.
- Model drift: The model cannot write final module bodies. The app extracts all module content locally.
- Wrong destination: If the target thinkspace cannot be resolved, the assistant asks the user to choose instead of guessing.
- Hidden failures: The plan stays visible by default with disabled Apply on mismatch, so users can inspect the action before any write.
- Scope creep: Keep this first version on Canvas Organizer. A separate Planning Agent can come later after this exact-copy workflow works reliably.

## Completion Criteria

- A long note can be converted into clusters and exact-copy note blocks from a single Canvas Organizer request.
- The original long note remains visible by default.
- The review UI is visible by default and shows source note, target thinkspace, clusters, module previews, and the original-visible badge.
- Hash mismatch blocks apply.
- New note bodies are byte-for-byte equivalent to the selected source substrings when encoded as UTF-8.
- Focused tests pass.
- Full app build passes.

## Inline Execution Notes

- Implemented `NoteStructureSourceSnapshot`, `PendingNoteStructurePlan`, cluster/module proposal models, SHA-256 body hashing, UTF-16 exact-copy extraction, and hash/range validation.
- Added `propose_note_structure_plan` to the Canvas Organizer tool path and parse it into a pending review plan instead of mutating canvas state directly.
- Added full active note body context through the note focus context provider and appended source note UUID/title/body hash instructions into Cosmo's context block.
- Added a visible-by-default Cosmo review card for note structure plans with source note, original-visible badge, cluster/module previews, disabled Apply on validation error, Revise, Cancel, and Apply.
- Added `NoteStructureApplyService` to create exact-copy module notes, place them as canvas blocks, update target thinkspace metadata, and preserve the original note.
- Updated Canvas Organizer prompt/seed prompt so long-note structuring uses exact source ranges and keeps the source note visible by default.
- Verification run: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS test -only-testing:CosmoOSTests/NoteStructurePlanTests -only-testing:CosmoOSTests/CosmoWindowContextSessionTests` passed.
- Verification run: `xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS build` passed.
- Verification run: `git diff --check` passed.
