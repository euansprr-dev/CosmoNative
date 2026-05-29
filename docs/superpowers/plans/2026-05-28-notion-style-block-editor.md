# Notion-Style Block Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a true Notion-style rich-document block editor for CosmoOS: semantic slash-menu block transformations, smooth block split/merge behavior, and hover-handle drag/drop reordering above and below blocks.

**Architecture:** Keep TextKit/AppKit responsible for typing, selection, caret geometry, and inline editing, while SwiftUI owns the `RichDocument` block tree and all semantic block operations. Introduce a pure `BlockOperations` engine with stable block paths, then migrate `BlockListView` from text-region grouping toward individually addressable block rows with hover affordances and drop targets.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit/TextKit, XCTest, existing `RichDocument`, `CosmoDocumentEditor`, `TextKitCoordinator`, `BlockListView`, and `DS` design tokens.

---

## Product Contract

- Slash menu commands transform or insert semantic `RichBlock` values, never fake the result by inserting markdown prefixes into TextKit storage.
- Headings, quote, bullet list, numbered list, checklist, divider, image, element, content, and research are all reachable through the same command model.
- Content and Research are first-class `RichBlockKind` cases because they need block-specific rendering, focus behavior, and future AI/research workflows.
- Return, Shift-Return, Backspace, Arrow Up, and Arrow Down work at block boundaries with stable focus and no visual jump.
- Dragging is only initiated from the hover handle, so text selection remains predictable.
- Drop indicators are shown above or below a block, with nested element/content/research children addressed by a path.
- All model mutation is testable without SwiftUI or AppKit.

## File Structure

- Create `Editor/BlockEditor/BlockPath.swift`: stable path model for root and nested block locations.
- Create `Editor/BlockEditor/BlockOperation.swift`: command/result types for transform, insert, split, merge, and move operations.
- Create `Editor/BlockEditor/BlockOperations.swift`: pure block tree mutation functions used by UI and tests.
- Create `Editor/BlockEditor/BlockCommandCatalog.swift`: slash-menu command model that maps `/` selections to semantic operations.
- Create `Editor/BlockEditor/BlockRowView.swift`: row shell that owns hover affordances, drag handle, and drop indicator.
- Create `Editor/BlockEditor/BlockTextEditorRow.swift`: single-block text editor bridge using existing `CosmoDocumentEditor`.
- Create `Editor/BlockEditor/BlockDropController.swift`: drag payload, drop target, and reorder policy.
- Modify `Editor/RichDocument.swift`: add `.content` and `.research` block kinds, helpers for textual block compatibility, and plain-text rendering.
- Modify `Editor/SlashCommandMenu.swift`: render `BlockCommand` rows and keep current keyboard behavior.
- Modify `Editor/RichTextEditor.swift`: make slash menu callbacks report command selection without direct block transformations.
- Modify `Editor/TextKitCoordinator.swift`: replace direct slash command execution with block-editor callbacks, preserving only TextKit-local typing and caret logic.
- Modify `Editor/CosmoDocumentEditor.swift`: expose block boundary events with cursor offsets and let parent apply `BlockOperations`.
- Modify `Editor/BlockEditor/BlockListView.swift`: render block rows, own command execution, focus, split/merge, and drag/drop.
- Modify `Editor/BlockEditor/ElementBlockView.swift`: render nested children through path-aware `BlockListView`.
- Keep `Editor/BlockEditor/TextRegionView.swift` during migration as a fallback for unsupported grouped text regions; remove its use from root block rendering once all text row tests pass.
- Test `Tests/CosmoOSTests/BlockOperationsTests.swift`: pure transform/insert/split/merge/move coverage.
- Test `Tests/CosmoOSTests/BlockCommandCatalogTests.swift`: slash menu command mapping and search coverage.
- Test `Tests/CosmoOSTests/BlockDragDropTests.swift`: root and nested reorder policy coverage.
- Modify `Tests/CosmoOSTests/RichDocumentTests.swift`: content/research Codable and plain-text coverage.

---

## Task 1: Block Path Model

**Files:**
- Create: `Editor/BlockEditor/BlockPath.swift`
- Create: `Tests/CosmoOSTests/BlockOperationsTests.swift`

- [ ] **Step 1: Write failing path tests**

Create `Tests/CosmoOSTests/BlockOperationsTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class BlockOperationsTests: XCTestCase {
    func testBlockPathAddressesRootAndNestedBlocks() throws {
        let root = BlockPath.root(index: 2)
        XCTAssertEqual(root.indices, [2])
        XCTAssertEqual(root.parent, nil)
        XCTAssertEqual(root.depth, 0)

        let nested = root.appendingChild(index: 1)
        XCTAssertEqual(nested.indices, [2, 1])
        XCTAssertEqual(nested.parent?.indices, [2])
        XCTAssertEqual(nested.depth, 1)
    }

    func testBlockPathRejectsNegativeIndices() {
        XCTAssertNil(BlockPath(indices: [-1]))
        XCTAssertNil(BlockPath(indices: [0, -1]))
        XCTAssertEqual(BlockPath(indices: [0, 2])?.indices, [0, 2])
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockOperationsTests test
```

Expected: FAIL with missing `BlockPath`.

- [ ] **Step 3: Implement `BlockPath`**

Create `Editor/BlockEditor/BlockPath.swift`:

```swift
import Foundation

struct BlockPath: Codable, Equatable, Hashable, Sendable {
    let indices: [Int]

    init?(indices: [Int]) {
        guard !indices.isEmpty, indices.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        self.indices = indices
    }

    static func root(index: Int) -> BlockPath {
        guard let path = BlockPath(indices: [index]) else {
            preconditionFailure("Root block index must be non-negative")
        }
        return path
    }

    var depth: Int {
        indices.count - 1
    }

    var parent: BlockPath? {
        guard indices.count > 1 else { return nil }
        return BlockPath(indices: Array(indices.dropLast()))
    }

    var indexInParent: Int {
        indices[indices.count - 1]
    }

    func appendingChild(index: Int) -> BlockPath {
        guard let path = BlockPath(indices: indices + [index]) else {
            preconditionFailure("Child block index must be non-negative")
        }
        return path
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockOperationsTests test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Editor/BlockEditor/BlockPath.swift Tests/CosmoOSTests/BlockOperationsTests.swift
git commit -m "feat: add block path model"
```

---

## Task 2: Content And Research Block Kinds

**Files:**
- Modify: `Editor/RichDocument.swift`
- Modify: `Tests/CosmoOSTests/RichDocumentTests.swift`

- [ ] **Step 1: Add failing RichDocument tests**

Append to `Tests/CosmoOSTests/RichDocumentTests.swift`:

```swift
func testContentAndResearchBlocksRoundTripThroughCodable() throws {
    let document = RichDocument(blocks: [
        RichBlock(kind: .content, inlines: [.text("Draft the story")]),
        RichBlock(kind: .research, inlines: [.text("Find source material")])
    ])

    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(RichDocument.self, from: data)

    XCTAssertEqual(decoded.blocks.map(\.kind), [.content, .research])
    XCTAssertEqual(decoded.blocks.map(\.plainInlineText), ["Draft the story", "Find source material"])
}

func testContentAndResearchBlocksContributePlainText() {
    let document = RichDocument(blocks: [
        RichBlock(kind: .content, inlines: [.text("Draft the story")]),
        RichBlock(kind: .research, inlines: [.text("Find source material")])
    ])

    XCTAssertEqual(document.plainText, "Draft the story\nFind source material")
}
```

- [ ] **Step 2: Run failing RichDocument tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentTests test
```

Expected: FAIL with missing `RichBlockKind.content` and `RichBlockKind.research`.

- [ ] **Step 3: Add block kinds and text compatibility**

In `Editor/RichDocument.swift`, update `RichBlockKind`:

```swift
enum RichBlockKind: String, Codable, CaseIterable, Hashable, Sendable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case quote
    case divider
    case bulletList
    case numberedList
    case checklist
    case image
    case element
    case content
    case research

    var headingLevelInt: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        default: return nil
        }
    }

    var isTextEditableBlock: Bool {
        switch self {
        case .paragraph, .heading1, .heading2, .heading3, .quote, .bulletList, .numberedList, .checklist, .content, .research:
            return true
        case .divider, .image, .element:
            return false
        }
    }

    var splitContinuationKind: RichBlockKind {
        switch self {
        case .heading1, .heading2, .heading3, .quote, .content, .research:
            return .paragraph
        case .bulletList:
            return .bulletList
        case .numberedList:
            return .numberedList
        case .checklist:
            return .checklist
        case .paragraph:
            return .paragraph
        case .divider, .image, .element:
            return .paragraph
        }
    }
}
```

- [ ] **Step 4: Ensure plain text includes content and research**

In `RichDocument.plainText(for:depth:)`, add these cases immediately after `.checklist` and before `.image`:

```swift
case .content:
    prefix = ""
case .research:
    prefix = ""
```

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Editor/RichDocument.swift Tests/CosmoOSTests/RichDocumentTests.swift
git commit -m "feat: add content and research block kinds"
```

---

## Task 3: Pure Block Operations

**Files:**
- Create: `Editor/BlockEditor/BlockOperation.swift`
- Create: `Editor/BlockEditor/BlockOperations.swift`
- Modify: `Tests/CosmoOSTests/BlockOperationsTests.swift`

- [ ] **Step 1: Add failing operation tests**

Append to `Tests/CosmoOSTests/BlockOperationsTests.swift`:

```swift
func testTransformPreservesInlineContentAndChangesKind() throws {
    let id = UUID()
    let document = RichDocument(blocks: [
        RichBlock(id: id, kind: .paragraph, inlines: [.text("Launch idea")])
    ])

    let result = try BlockOperations.transformBlock(
        in: document,
        at: .root(index: 0),
        to: .heading2
    )

    XCTAssertEqual(result.document.blocks[0].id, id)
    XCTAssertEqual(result.document.blocks[0].kind, .heading2)
    XCTAssertEqual(result.document.blocks[0].plainInlineText, "Launch idea")
    XCTAssertEqual(result.focusPath, .root(index: 0))
}

func testInsertAfterAddsBlockAndFocusesInsertedBlock() throws {
    let document = RichDocument(blocks: [.paragraph("A")])
    let inserted = RichBlock(kind: .checklist, inlines: [.text("")], checked: false)

    let result = try BlockOperations.insertBlock(inserted, in: document, after: .root(index: 0))

    XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["A", ""])
    XCTAssertEqual(result.document.blocks[1].kind, .checklist)
    XCTAssertEqual(result.focusPath, .root(index: 1))
}

func testSplitParagraphAtTextOffsetCreatesTwoBlocks() throws {
    let document = RichDocument(blocks: [
        RichBlock(kind: .paragraph, inlines: [.text("Hello world")])
    ])

    let result = try BlockOperations.splitTextBlock(
        in: document,
        at: .root(index: 0),
        utf16Offset: 5
    )

    XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["Hello", " world"])
    XCTAssertEqual(result.document.blocks.map(\.kind), [.paragraph, .paragraph])
    XCTAssertEqual(result.focusPath, .root(index: 1))
}

func testHeadingSplitContinuesAsParagraph() throws {
    let document = RichDocument(blocks: [
        RichBlock(kind: .heading1, inlines: [.text("Hello world")])
    ])

    let result = try BlockOperations.splitTextBlock(
        in: document,
        at: .root(index: 0),
        utf16Offset: 5
    )

    XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["Hello", " world"])
    XCTAssertEqual(result.document.blocks.map(\.kind), [.heading1, .paragraph])
}

func testMergeBackwardCombinesTextBlocksAndFocusesMergedBlock() throws {
    let firstID = UUID()
    let document = RichDocument(blocks: [
        RichBlock(id: firstID, kind: .paragraph, inlines: [.text("Hello")]),
        RichBlock(kind: .paragraph, inlines: [.text(" world")])
    ])

    let result = try BlockOperations.mergeBackward(in: document, at: .root(index: 1))

    XCTAssertEqual(result.document.blocks.count, 1)
    XCTAssertEqual(result.document.blocks[0].id, firstID)
    XCTAssertEqual(result.document.blocks[0].plainInlineText, "Hello world")
    XCTAssertEqual(result.focusPath, .root(index: 0))
    XCTAssertEqual(result.caretUTF16Offset, 11)
}

func testMoveRootBlockBeforeAnotherRootBlock() throws {
    let document = RichDocument(blocks: [.paragraph("A"), .paragraph("B"), .paragraph("C")])

    let result = try BlockOperations.moveBlock(
        in: document,
        from: .root(index: 2),
        to: BlockDropTarget(parent: nil, index: 0)
    )

    XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["C", "A", "B"])
    XCTAssertEqual(result.focusPath, .root(index: 0))
}
```

- [ ] **Step 2: Run failing operation tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockOperationsTests test
```

Expected: FAIL with missing `BlockOperations`, `BlockOperationResult`, and `BlockDropTarget`.

- [ ] **Step 3: Add operation result types**

Create `Editor/BlockEditor/BlockOperation.swift`:

```swift
import Foundation

enum BlockOperationError: Error, Equatable {
    case blockNotFound(BlockPath)
    case parentNotFound(BlockPath)
    case unsupportedBlockKind(RichBlockKind)
    case invalidTextOffset(Int)
    case cannotMoveBlockIntoItself
}

struct BlockOperationResult: Equatable {
    var document: RichDocument
    var focusPath: BlockPath?
    var caretUTF16Offset: Int?

    init(document: RichDocument, focusPath: BlockPath? = nil, caretUTF16Offset: Int? = nil) {
        self.document = document
        self.focusPath = focusPath
        self.caretUTF16Offset = caretUTF16Offset
    }
}

struct BlockDropTarget: Equatable, Hashable, Sendable {
    var parent: BlockPath?
    var index: Int

    init(parent: BlockPath?, index: Int) {
        precondition(index >= 0, "Drop index must be non-negative")
        self.parent = parent
        self.index = index
    }
}
```

- [ ] **Step 4: Add pure operations**

Create `Editor/BlockEditor/BlockOperations.swift`:

```swift
import Foundation

enum BlockOperations {
    static func transformBlock(
        in document: RichDocument,
        at path: BlockPath,
        to kind: RichBlockKind
    ) throws -> BlockOperationResult {
        var document = document
        var block = try block(in: document, at: path)
        block.kind = kind
        if kind == .checklist, block.checked == nil {
            block.checked = false
        }
        if kind != .checklist {
            block.checked = nil
        }
        try replaceBlock(block, in: &document, at: path)
        return BlockOperationResult(document: document, focusPath: path)
    }

    static func insertBlock(
        _ block: RichBlock,
        in document: RichDocument,
        after path: BlockPath
    ) throws -> BlockOperationResult {
        let target = BlockDropTarget(parent: path.parent, index: path.indexInParent + 1)
        return try insertBlock(block, in: document, at: target)
    }

    static func insertBlock(
        _ block: RichBlock,
        in document: RichDocument,
        at target: BlockDropTarget
    ) throws -> BlockOperationResult {
        var document = document
        try insert(block, in: &document, at: target)
        let focusPath = target.parent?.appendingChild(index: target.index) ?? .root(index: target.index)
        return BlockOperationResult(document: document, focusPath: focusPath)
    }

    static func splitTextBlock(
        in document: RichDocument,
        at path: BlockPath,
        utf16Offset: Int
    ) throws -> BlockOperationResult {
        var document = document
        let original = try block(in: document, at: path)
        guard original.kind.isTextEditableBlock else {
            throw BlockOperationError.unsupportedBlockKind(original.kind)
        }

        let text = original.plainInlineText
        guard let splitIndex = String.Index(utf16Offset: utf16Offset, in: text) else {
            throw BlockOperationError.invalidTextOffset(utf16Offset)
        }

        var before = original
        before.inlines = [.text(String(text[..<splitIndex]))]

        var after = RichBlock(
            kind: original.kind.splitContinuationKind,
            inlines: [.text(String(text[splitIndex...]))],
            checked: original.kind == .checklist ? false : nil
        )

        if original.kind == .numberedList {
            after.kind = .numberedList
        }

        try replaceBlock(before, in: &document, at: path)
        let insertionTarget = BlockDropTarget(parent: path.parent, index: path.indexInParent + 1)
        try insert(after, in: &document, at: insertionTarget)
        let focusPath = path.parent?.appendingChild(index: path.indexInParent + 1) ?? .root(index: path.indexInParent + 1)
        return BlockOperationResult(document: document, focusPath: focusPath, caretUTF16Offset: 0)
    }

    static func mergeBackward(
        in document: RichDocument,
        at path: BlockPath
    ) throws -> BlockOperationResult {
        guard path.indexInParent > 0 else {
            throw BlockOperationError.blockNotFound(path)
        }

        var document = document
        let current = try block(in: document, at: path)
        let previousPath = path.parent?.appendingChild(index: path.indexInParent - 1) ?? .root(index: path.indexInParent - 1)
        var previous = try block(in: document, at: previousPath)

        guard previous.kind.isTextEditableBlock, current.kind.isTextEditableBlock else {
            throw BlockOperationError.unsupportedBlockKind(current.kind)
        }

        let mergedText = previous.plainInlineText + current.plainInlineText
        previous.inlines = [.text(mergedText)]
        try replaceBlock(previous, in: &document, at: previousPath)
        try removeBlock(in: &document, at: path)

        return BlockOperationResult(
            document: document,
            focusPath: previousPath,
            caretUTF16Offset: mergedText.utf16.count
        )
    }

    static func moveBlock(
        in document: RichDocument,
        from source: BlockPath,
        to target: BlockDropTarget
    ) throws -> BlockOperationResult {
        if let parent = target.parent, parent.indices.starts(with: source.indices) {
            throw BlockOperationError.cannotMoveBlockIntoItself
        }

        var document = document
        let moving = try block(in: document, at: source)
        try removeBlock(in: &document, at: source)

        var adjustedTarget = target
        if source.parent == target.parent, source.indexInParent < target.index {
            adjustedTarget.index -= 1
        }

        try insert(moving, in: &document, at: adjustedTarget)
        let focusPath = adjustedTarget.parent?.appendingChild(index: adjustedTarget.index) ?? .root(index: adjustedTarget.index)
        return BlockOperationResult(document: document, focusPath: focusPath)
    }

    private static func block(in document: RichDocument, at path: BlockPath) throws -> RichBlock {
        guard let block = block(in: document.blocks, indices: path.indices) else {
            throw BlockOperationError.blockNotFound(path)
        }
        return block
    }

    private static func block(in blocks: [RichBlock], indices: [Int]) -> RichBlock? {
        guard let first = indices.first, blocks.indices.contains(first) else { return nil }
        if indices.count == 1 { return blocks[first] }
        return block(in: blocks[first].children, indices: Array(indices.dropFirst()))
    }

    private static func replaceBlock(_ block: RichBlock, in document: inout RichDocument, at path: BlockPath) throws {
        try mutateChildren(in: &document.blocks, indices: path.indices) { siblings, index in
            siblings[index] = block
        }
    }

    private static func removeBlock(in document: inout RichDocument, at path: BlockPath) throws {
        try mutateChildren(in: &document.blocks, indices: path.indices) { siblings, index in
            siblings.remove(at: index)
        }
    }

    private static func insert(_ block: RichBlock, in document: inout RichDocument, at target: BlockDropTarget) throws {
        if let parent = target.parent {
            try mutateBlock(in: &document.blocks, indices: parent.indices) { parentBlock in
                guard target.index <= parentBlock.children.count else {
                    throw BlockOperationError.parentNotFound(parent)
                }
                parentBlock.children.insert(block, at: target.index)
            }
        } else {
            guard target.index <= document.blocks.count else {
                throw BlockOperationError.parentNotFound(.root(index: target.index))
            }
            document.blocks.insert(block, at: target.index)
        }
    }

    private static func mutateChildren(
        in blocks: inout [RichBlock],
        indices: [Int],
        mutation: (inout [RichBlock], Int) throws -> Void
    ) throws {
        guard let first = indices.first, blocks.indices.contains(first) else {
            throw BlockOperationError.blockNotFound(BlockPath(indices: indices) ?? .root(index: 0))
        }
        if indices.count == 1 {
            try mutation(&blocks, first)
        } else {
            try mutateChildren(in: &blocks[first].children, indices: Array(indices.dropFirst()), mutation: mutation)
        }
    }

    private static func mutateBlock(
        in blocks: inout [RichBlock],
        indices: [Int],
        mutation: (inout RichBlock) throws -> Void
    ) throws {
        guard let first = indices.first, blocks.indices.contains(first) else {
            throw BlockOperationError.blockNotFound(BlockPath(indices: indices) ?? .root(index: 0))
        }
        if indices.count == 1 {
            try mutation(&blocks[first])
        } else {
            try mutateBlock(in: &blocks[first].children, indices: Array(indices.dropFirst()), mutation: mutation)
        }
    }
}

private extension String.Index {
    init?(utf16Offset: Int, in string: String) {
        guard utf16Offset >= 0,
              let utf16Index = string.utf16.index(string.utf16.startIndex, offsetBy: utf16Offset, limitedBy: string.utf16.endIndex),
              let index = String.Index(utf16Index, within: string) else {
            return nil
        }
        self = index
    }
}
```

- [ ] **Step 5: Run operation tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockOperationsTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Editor/BlockEditor/BlockOperation.swift Editor/BlockEditor/BlockOperations.swift Tests/CosmoOSTests/BlockOperationsTests.swift
git commit -m "feat: add pure block operations"
```

---

## Task 4: Semantic Slash Command Catalog

**Files:**
- Create: `Editor/BlockEditor/BlockCommandCatalog.swift`
- Create: `Tests/CosmoOSTests/BlockCommandCatalogTests.swift`
- Modify: `Editor/SlashCommandMenu.swift`
- Modify: `Editor/RichTextEditor.swift`

- [ ] **Step 1: Write failing command catalog tests**

Create `Tests/CosmoOSTests/BlockCommandCatalogTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class BlockCommandCatalogTests: XCTestCase {
    func testBaseCommandsContainAllBlockTypesShownInSlashMenu() {
        let commands = BlockCommandCatalog.baseCommands

        XCTAssertTrue(commands.contains { $0.action == .transform(.heading1) })
        XCTAssertTrue(commands.contains { $0.action == .transform(.heading2) })
        XCTAssertTrue(commands.contains { $0.action == .transform(.heading3) })
        XCTAssertTrue(commands.contains { $0.action == .transform(.checklist) })
        XCTAssertTrue(commands.contains { $0.action == .transform(.bulletList) })
        XCTAssertTrue(commands.contains { $0.action == .transform(.numberedList) })
        XCTAssertTrue(commands.contains { $0.action == .transform(.quote) })
        XCTAssertTrue(commands.contains { $0.action == .replaceOrInsert(.divider) })
        XCTAssertTrue(commands.contains { $0.action == .replaceOrInsert(.image) })
        XCTAssertTrue(commands.contains { $0.action == .replaceOrInsert(.content) })
        XCTAssertTrue(commands.contains { $0.action == .replaceOrInsert(.research) })
        XCTAssertTrue(commands.contains { $0.action == .openWritingAI })
        XCTAssertTrue(commands.contains { $0.action == .openElementsSubmenu })
    }

    func testFilteringMatchesTitleSubtitleAndAliases() {
        let filtered = BlockCommandCatalog.filteredCommands(query: "todo")
        XCTAssertEqual(filtered.first?.action, .transform(.checklist))

        let research = BlockCommandCatalog.filteredCommands(query: "source")
        XCTAssertEqual(research.first?.action, .replaceOrInsert(.research))
    }
}
```

- [ ] **Step 2: Run failing command tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockCommandCatalogTests test
```

Expected: FAIL with missing `BlockCommandCatalog`.

- [ ] **Step 3: Implement command catalog**

Create `Editor/BlockEditor/BlockCommandCatalog.swift`:

```swift
import Foundation

struct BlockCommand: Identifiable, Equatable, Hashable {
    enum Action: Equatable, Hashable {
        case transform(RichBlockKind)
        case replaceOrInsert(RichBlockKind)
        case insertElement(DocumentElementDefinition)
        case createElement
        case openElementsSubmenu
        case openWritingAI
    }

    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var aliases: [String]
    var action: Action

    var searchableText: String {
        ([title, subtitle] + aliases)
            .joined(separator: " ")
            .lowercased()
    }
}

enum BlockCommandCatalog {
    static let baseCommands: [BlockCommand] = [
        BlockCommand(
            id: "writing-ai",
            title: "Writing AI",
            subtitle: "Draft, rewrite, or continue this block",
            systemImage: "sparkles",
            aliases: ["ai", "write", "assistant"],
            action: .openWritingAI
        ),
        BlockCommand(
            id: "heading-1",
            title: "Heading 1",
            subtitle: "Large section heading",
            systemImage: "textformat.size.larger",
            aliases: ["h1", "title"],
            action: .transform(.heading1)
        ),
        BlockCommand(
            id: "heading-2",
            title: "Heading 2",
            subtitle: "Medium section heading",
            systemImage: "textformat.size",
            aliases: ["h2", "subtitle"],
            action: .transform(.heading2)
        ),
        BlockCommand(
            id: "heading-3",
            title: "Heading 3",
            subtitle: "Small section heading",
            systemImage: "textformat",
            aliases: ["h3"],
            action: .transform(.heading3)
        ),
        BlockCommand(
            id: "checklist",
            title: "Checklist",
            subtitle: "Track tasks with checkboxes",
            systemImage: "checklist",
            aliases: ["todo", "task", "checkbox"],
            action: .transform(.checklist)
        ),
        BlockCommand(
            id: "bullet-list",
            title: "Bullet List",
            subtitle: "Create a bulleted list item",
            systemImage: "list.bullet",
            aliases: ["ul", "list"],
            action: .transform(.bulletList)
        ),
        BlockCommand(
            id: "numbered-list",
            title: "Numbered List",
            subtitle: "Create an ordered list item",
            systemImage: "list.number",
            aliases: ["ol", "ordered"],
            action: .transform(.numberedList)
        ),
        BlockCommand(
            id: "quote",
            title: "Quote",
            subtitle: "Emphasize a passage",
            systemImage: "quote.opening",
            aliases: ["blockquote"],
            action: .transform(.quote)
        ),
        BlockCommand(
            id: "divider",
            title: "Divider",
            subtitle: "Separate sections",
            systemImage: "minus",
            aliases: ["line", "separator", "rule"],
            action: .replaceOrInsert(.divider)
        ),
        BlockCommand(
            id: "image",
            title: "Image",
            subtitle: "Insert an image block",
            systemImage: "photo",
            aliases: ["picture", "media"],
            action: .replaceOrInsert(.image)
        ),
        BlockCommand(
            id: "content",
            title: "Content Block",
            subtitle: "Create a structured writing block",
            systemImage: "doc.text",
            aliases: ["draft", "post", "article"],
            action: .replaceOrInsert(.content)
        ),
        BlockCommand(
            id: "research",
            title: "Research Block",
            subtitle: "Collect sources and findings",
            systemImage: "magnifyingglass",
            aliases: ["source", "sources", "inquiry"],
            action: .replaceOrInsert(.research)
        ),
        BlockCommand(
            id: "elements",
            title: "Elements",
            subtitle: "Insert a reusable custom block",
            systemImage: "square.stack.3d.up",
            aliases: ["custom", "template"],
            action: .openElementsSubmenu
        )
    ]

    static func filteredCommands(query: String) -> [BlockCommand] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return baseCommands }

        return baseCommands
            .map { command -> (BlockCommand, Int)? in
                if command.title.lowercased().hasPrefix(normalized) { return (command, 0) }
                if command.searchableText.contains(normalized) { return (command, 1) }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
```

- [ ] **Step 4: Adapt slash menu UI to command rows**

Modify `Editor/SlashCommandMenu.swift` so the row view can be initialized with either legacy `SlashCommand` or new `BlockCommand`. Preserve visual styling and keyboard navigation. Add this adapter near the menu model:

```swift
struct SlashMenuRowModel: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
}

extension SlashMenuRowModel {
    init(command: BlockCommand) {
        self.id = command.id
        self.title = command.title
        self.subtitle = command.subtitle
        self.systemImage = command.systemImage
    }

    init(command: SlashCommand) {
        self.id = command.id.uuidString
        self.title = command.title
        self.subtitle = command.subtitle
        self.systemImage = command.systemImage
    }
}
```

Update internal row rendering to consume `SlashMenuRowModel`. Keep existing legacy initializer available so current call sites compile during the migration.

- [ ] **Step 5: Run command tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockCommandCatalogTests test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Editor/BlockEditor/BlockCommandCatalog.swift Editor/SlashCommandMenu.swift Editor/RichTextEditor.swift Tests/CosmoOSTests/BlockCommandCatalogTests.swift
git commit -m "feat: add semantic block command catalog"
```

---

## Task 5: Single Block Text Row

**Files:**
- Create: `Editor/BlockEditor/BlockTextEditorRow.swift`
- Create: `Editor/BlockEditor/BlockRowView.swift`
- Modify: `Editor/BlockEditor/BlockFocusCoordinator.swift`
- Modify: `Editor/BlockEditor/BlockListView.swift`

- [ ] **Step 1: Add row identity helpers**

Modify `Editor/BlockEditor/BlockFocusCoordinator.swift` to support path-aware focus without breaking ID focus:

```swift
struct BlockFocusTarget: Equatable, Hashable {
    var blockID: UUID
    var path: BlockPath
}
```

Add storage:

```swift
private var pathsByID: [UUID: BlockPath] = [:]
```

Add methods:

```swift
func register(_ id: UUID, path: BlockPath) {
    register(id)
    pathsByID[id] = path
}

func path(for id: UUID) -> BlockPath? {
    pathsByID[id]
}

func clearPaths() {
    pathsByID.removeAll()
}
```

- [ ] **Step 2: Create text row view**

Create `Editor/BlockEditor/BlockTextEditorRow.swift`:

```swift
import AppKit
import SwiftUI

struct BlockTextEditorRow: View {
    @Binding var block: RichBlock

    let path: BlockPath
    let focusCoordinator: BlockFocusCoordinator
    let fontSize: CGFloat
    let placeholder: String
    let darkMode: Bool
    let overrideTextColor: NSColor?
    let allowSlashCommands: Bool
    let allowMentions: Bool
    let allowSelectionMenu: Bool
    let allowImages: Bool
    let typewriterMode: Bool
    let editorTargetID: String?
    let navigationTargetID: UUID?
    let onSelectionChanged: ((EditorSelectionSnapshot) -> Void)?
    let onBoundaryCommand: (EditorBoundaryCommand, BlockPath) -> Bool
    let onDocumentChange: () -> Void

    var body: some View {
        CosmoDocumentEditor(
            document: singleBlockDocumentBinding,
            fontSize: fontSize,
            placeholder: placeholder,
            darkMode: darkMode,
            overrideTextColor: overrideTextColor,
            allowSlashCommands: allowSlashCommands,
            allowMentions: allowMentions,
            allowSelectionMenu: allowSelectionMenu,
            allowImages: allowImages,
            typewriterMode: typewriterMode,
            scrollsInternally: false,
            editorTargetID: editorTargetID,
            navigationTargetID: navigationTargetID,
            onSelectionChanged: onSelectionChanged,
            onBoundaryCommand: { command in
                onBoundaryCommand(command, path)
            },
            onDocumentChange: { _, _ in
                onDocumentChange()
            }
        )
        .onAppear {
            focusCoordinator.register(block.id, path: path)
        }
    }

    private var singleBlockDocumentBinding: Binding<RichDocument> {
        Binding(
            get: {
                RichDocument(blocks: [block])
            },
            set: { nextDocument in
                guard let nextBlock = nextDocument.blocks.first else { return }
                if block != nextBlock {
                    block = nextBlock
                }
            }
        )
    }
}
```

- [ ] **Step 3: Create row shell**

Create `Editor/BlockEditor/BlockRowView.swift`:

```swift
import SwiftUI

struct BlockRowView<Content: View>: View {
    let blockID: UUID
    let path: BlockPath
    let isDropTargetAbove: Bool
    let isDropTargetBelow: Bool
    let onDragHandleHover: (Bool) -> Void
    let onBeginDrag: () -> Void
    @ViewBuilder var content: Content

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            dropIndicator(isVisible: isDropTargetAbove)
            HStack(alignment: .top, spacing: DS.space6) {
                dragHandle
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            dropIndicator(isVisible: isDropTargetBelow)
        }
        .onHover { hovering in
            isHovering = hovering
            onDragHandleHover(hovering)
        }
    }

    private var dragHandle: some View {
        Button(action: onBeginDrag) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .accessibilityLabel("Move block")
    }

    private func dropIndicator(isVisible: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: isVisible ? 2 : 0)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isVisible)
    }
}
```

- [ ] **Step 4: Render text-editable rows in `BlockListView`**

Modify `Editor/BlockEditor/BlockListView.swift` to add:

```swift
private func blockBinding(at path: BlockPath) -> Binding<RichBlock>? {
    guard path.indices.count == 1, document.blocks.indices.contains(path.indexInParent) else {
        return nil
    }

    return Binding(
        get: { document.blocks[path.indexInParent] },
        set: { nextBlock in
            guard document.blocks.indices.contains(path.indexInParent),
                  document.blocks[path.indexInParent] != nextBlock else {
                return
            }
            document.blocks[path.indexInParent] = nextBlock
            emitDocumentChange()
        }
    )
}
```

In `body`, replace `ForEach(regions)` with root blocks:

```swift
VStack(alignment: .leading, spacing: DS.space8) {
    ForEach(Array(document.blocks.enumerated()), id: \.element.id) { index, block in
        let path = BlockPath.root(index: index)
        blockRow(for: block, at: path)
    }
}
```

Add a `@ViewBuilder`:

```swift
@ViewBuilder
private func blockRow(for block: RichBlock, at path: BlockPath) -> some View {
    BlockRowView(
        blockID: block.id,
        path: path,
        isDropTargetAbove: false,
        isDropTargetBelow: false,
        onDragHandleHover: { _ in },
        onBeginDrag: { }
    ) {
        if block.kind.isTextEditableBlock, let binding = blockBinding(at: path) {
            BlockTextEditorRow(
                block: binding,
                path: path,
                focusCoordinator: resolvedFocusCoordinator,
                fontSize: fontSize,
                placeholder: placeholder,
                darkMode: darkMode,
                overrideTextColor: overrideTextColor,
                allowSlashCommands: allowSlashCommands,
                allowMentions: allowMentions,
                allowSelectionMenu: allowSelectionMenu,
                allowImages: allowImages,
                typewriterMode: typewriterMode,
                editorTargetID: editorTargetID,
                navigationTargetID: navigationTargetID,
                onSelectionChanged: onSelectionChanged,
                onBoundaryCommand: handleBoundaryCommand,
                onDocumentChange: emitDocumentChange
            )
        } else if block.kind == .element, let binding = blockBinding(at: path) {
            ElementBlockView(
                block: binding,
                focusCoordinator: resolvedFocusCoordinator,
                fontSize: fontSize,
                darkMode: darkMode,
                overrideTextColor: overrideTextColor,
                allowSlashCommands: allowSlashCommands,
                allowMentions: allowMentions,
                allowSelectionMenu: allowSelectionMenu,
                allowImages: allowImages,
                typewriterMode: typewriterMode,
                editorTargetID: editorTargetID,
                navigationTargetID: navigationTargetID,
                onSelectionChanged: onSelectionChanged,
                onExitBody: { insertParagraph(after: path) },
                onElementChange: emitDocumentChange
            )
        } else {
            UnsupportedBlockRow(block: block)
        }
    }
}
```

Add a compact unsupported fallback in the same file:

```swift
private struct UnsupportedBlockRow: View {
    let block: RichBlock

    var body: some View {
        Text(block.plainInlineText.isEmpty ? block.kind.rawValue : block.plainInlineText)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild build -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -derivedDataPath /tmp/CosmoOSBlockEditorDerivedData
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Editor/BlockEditor/BlockTextEditorRow.swift Editor/BlockEditor/BlockRowView.swift Editor/BlockEditor/BlockFocusCoordinator.swift Editor/BlockEditor/BlockListView.swift
git commit -m "feat: render editable document block rows"
```

---

## Task 6: Slash Command Execution Through BlockOperations

**Files:**
- Modify: `Editor/TextKitCoordinator.swift`
- Modify: `Editor/RichTextEditor.swift`
- Modify: `Editor/CosmoDocumentEditor.swift`
- Modify: `Editor/BlockEditor/BlockTextEditorRow.swift`
- Modify: `Editor/BlockEditor/BlockListView.swift`

- [ ] **Step 1: Add slash request model**

Create these types in `Editor/BlockEditor/BlockOperation.swift`:

```swift
struct BlockSlashRequest: Equatable {
    var path: BlockPath
    var queryRange: NSRange
    var query: String
    var caretRect: CGRect
}

struct BlockTextSelection: Equatable {
    var path: BlockPath
    var utf16Offset: Int
    var selectedLength: Int
}
```

- [ ] **Step 2: Route slash request out of TextKit**

Modify `Editor/RichTextEditor.swift` and `TextKitEditorRepresentable` to add:

```swift
var onBlockSlashRequest: ((NSRange, String, CGRect) -> Void)?
```

In `TextKitCoordinator.handleSlashState`, replace direct menu ownership with:

```swift
let slashRange = NSRange(location: cursorLocation - 1, length: 1)
parent.onBlockSlashRequest?(slashRange, "", caretPosition(for: cursorLocation - 1, in: textView))
```

Keep the existing legacy `onSlashCommand` path behind `if parent.onBlockSlashRequest == nil` so current non-block call sites keep working during the migration.

- [ ] **Step 3: Convert row slash request to block slash request**

Modify `BlockTextEditorRow`:

```swift
let onWritingAIRequest: (() -> Void)?
let onSlashRequest: (BlockSlashRequest) -> Void
```

Pass to `CosmoDocumentEditor`:

```swift
onWritingAIRequest: onWritingAIRequest,
onBlockSlashRequest: { range, query, rect in
    onSlashRequest(BlockSlashRequest(path: path, queryRange: range, query: query, caretRect: rect))
}
```

Add this property to `CosmoDocumentEditor` and pass it through to `RichTextEditor`:

```swift
var onBlockSlashRequest: ((NSRange, String, CGRect) -> Void)? = nil
```

Add this property to `RichTextEditor` and `TextKitEditorRepresentable`:

```swift
var onBlockSlashRequest: ((NSRange, String, CGRect) -> Void)? = nil
```

After adding the new required row parameters, update the generic `BlockTextEditorRow` call in `BlockListView`:

```swift
onWritingAIRequest: onWritingAIRequest,
onSlashRequest: handleSlashRequest
```

- [ ] **Step 4: Execute block commands in `BlockListView`**

Add state to `BlockListView`:

```swift
@State private var activeSlashRequest: BlockSlashRequest?
@State private var slashQuery: String = ""
```

Add a request callback property to `BlockListView`:

```swift
var onWritingAIRequest: (() -> Void)? = nil
```

Pass from row:

```swift
onSlashRequest: { request in
    activeSlashRequest = request
    slashQuery = request.query
}
```

Add command execution:

```swift
private func execute(_ command: BlockCommand) {
    guard let request = activeSlashRequest else { return }

    do {
        let current = try currentBlock(at: request.path)
        let currentText = current.plainInlineText
        let onlySlashQuery = currentText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")

        let result: BlockOperationResult
        switch command.action {
        case .transform(let kind):
            result = try BlockOperations.transformBlock(in: document, at: request.path, to: kind)
        case .replaceOrInsert(let kind):
            let block = makeEmptyBlock(kind: kind)
            if onlySlashQuery {
                result = try BlockOperations.replaceBlock(in: document, at: request.path, with: block)
            } else {
                result = try BlockOperations.insertBlock(block, in: document, after: request.path)
            }
        case .insertElement(let definition):
            let block = RichBlock.element(definition, children: [.paragraph("")])
            if onlySlashQuery {
                result = try BlockOperations.replaceBlock(in: document, at: request.path, with: block)
            } else {
                result = try BlockOperations.insertBlock(block, in: document, after: request.path)
            }
        case .createElement:
            return
        case .openElementsSubmenu:
            return
        case .openWritingAI:
            onWritingAIRequest?()
            return
        }

        document = result.document
        emitDocumentChange()
        if let focusPath = result.focusPath {
            focusBlock(at: focusPath)
        }
        activeSlashRequest = nil
    } catch {
        assertionFailure("Block command failed: \(error)")
    }
}
```

Add helpers:

```swift
private func makeEmptyBlock(kind: RichBlockKind) -> RichBlock {
    switch kind {
    case .checklist:
        return RichBlock(kind: .checklist, inlines: [.text("")], checked: false)
    case .divider:
        return RichBlock(kind: .divider)
    case .image:
        return RichBlock(kind: .image)
    case .content:
        return RichBlock(kind: .content, inlines: [.text("")])
    case .research:
        return RichBlock(kind: .research, inlines: [.text("")])
    default:
        return RichBlock(kind: kind, inlines: [.text("")])
    }
}
```

Add `BlockOperations.replaceBlock` as a public operation:

```swift
static func replaceBlock(
    in document: RichDocument,
    at path: BlockPath,
    with block: RichBlock
) throws -> BlockOperationResult {
    var document = document
    try replaceBlock(block, in: &document, at: path)
    return BlockOperationResult(document: document, focusPath: path)
}
```

- [ ] **Step 5: Build and test commands**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockCommandCatalogTests -only-testing:CosmoOSTests/BlockOperationsTests test
xcodebuild build -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -derivedDataPath /tmp/CosmoOSBlockEditorDerivedData
```

Expected: tests PASS and build succeeds.

- [ ] **Step 6: Manual verification**

Run the app from Xcode or:

```bash
xcodebuild build -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -derivedDataPath /tmp/CosmoOSBlockEditorDerivedData
```

Verify:
- Type `/h1` in an empty paragraph and select Heading 1. The current block becomes a heading.
- Type `/todo` and select Checklist. The current block becomes a checklist.
- Type text, then use `/research`. A research block inserts below instead of replacing the text block.
- Type `/divider` in an empty block. The current block becomes a divider row.

- [ ] **Step 7: Commit**

```bash
git add Editor/TextKitCoordinator.swift Editor/RichTextEditor.swift Editor/CosmoDocumentEditor.swift Editor/BlockEditor/BlockTextEditorRow.swift Editor/BlockEditor/BlockListView.swift Editor/BlockEditor/BlockOperation.swift Editor/BlockEditor/BlockOperations.swift
git commit -m "feat: execute slash commands as block operations"
```

---

## Task 7: Split, Merge, And Boundary Behavior

**Files:**
- Modify: `Editor/CosmoDocumentEditor.swift`
- Modify: `Editor/TextKitCoordinator.swift`
- Modify: `Editor/BlockEditor/BlockTextEditorRow.swift`
- Modify: `Editor/BlockEditor/BlockListView.swift`
- Modify: `Tests/CosmoOSTests/BlockOperationsTests.swift`

- [ ] **Step 1: Add empty-list exit operation tests**

Append to `Tests/CosmoOSTests/BlockOperationsTests.swift`:

```swift
func testReturnOnEmptyChecklistExitsToParagraph() throws {
    let document = RichDocument(blocks: [
        RichBlock(kind: .checklist, inlines: [.text("")], checked: false)
    ])

    let result = try BlockOperations.exitEmptyListBlock(in: document, at: .root(index: 0))

    XCTAssertEqual(result.document.blocks[0].kind, .paragraph)
    XCTAssertEqual(result.document.blocks[0].checked, nil)
    XCTAssertEqual(result.focusPath, .root(index: 0))
}

func testBackspaceAtStartOfEmptyParagraphRemovesBlock() throws {
    let document = RichDocument(blocks: [.paragraph("A"), .paragraph("")])

    let result = try BlockOperations.deleteEmptyBlockBackward(in: document, at: .root(index: 1))

    XCTAssertEqual(result.document.blocks.map(\.plainInlineText), ["A"])
    XCTAssertEqual(result.focusPath, .root(index: 0))
}
```

- [ ] **Step 2: Implement boundary operations**

Add to `Editor/BlockEditor/BlockOperations.swift`:

```swift
static func exitEmptyListBlock(
    in document: RichDocument,
    at path: BlockPath
) throws -> BlockOperationResult {
    var block = try block(in: document, at: path)
    guard [.bulletList, .numberedList, .checklist].contains(block.kind),
          block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw BlockOperationError.unsupportedBlockKind(block.kind)
    }

    block.kind = .paragraph
    block.checked = nil
    var document = document
    try replaceBlock(block, in: &document, at: path)
    return BlockOperationResult(document: document, focusPath: path, caretUTF16Offset: 0)
}

static func deleteEmptyBlockBackward(
    in document: RichDocument,
    at path: BlockPath
) throws -> BlockOperationResult {
    let block = try block(in: document, at: path)
    guard block.kind.isTextEditableBlock,
          block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          path.indexInParent > 0 else {
        throw BlockOperationError.unsupportedBlockKind(block.kind)
    }

    var document = document
    try removeBlock(in: &document, at: path)
    let focusPath = path.parent?.appendingChild(index: path.indexInParent - 1) ?? .root(index: path.indexInParent - 1)
    return BlockOperationResult(document: document, focusPath: focusPath)
}
```

- [ ] **Step 3: Report Return and Backspace with offsets**

Extend `EditorBoundaryCommand` in `Editor/CosmoDocumentEditor.swift`:

```swift
enum EditorBoundaryCommand {
    case moveToPreviousBlock
    case moveToNextBlock
    case deleteBackwardAtStart
    case insertNewlineOnEmptyFinalLine
    case splitBlockAtCursor(utf16Offset: Int)
    case softNewlineAtCursor(utf16Offset: Int)
}
```

In `TextKitCoordinator`, when Return is pressed in a block editor row:
- If Shift is held, let TextKit insert a newline.
- If slash menu is open, select the command.
- Otherwise call `.splitBlockAtCursor(utf16Offset: selectedRange.location)`.

For Backspace at cursor zero, keep `.deleteBackwardAtStart`.

- [ ] **Step 4: Handle new boundary commands in `BlockListView`**

Update `handleBoundaryCommand`:

```swift
case .splitBlockAtCursor(let utf16Offset):
    return handleSplitBlock(at: path, utf16Offset: utf16Offset)
case .softNewlineAtCursor:
    return false
```

Add:

```swift
private func handleSplitBlock(at path: BlockPath, utf16Offset: Int) -> Bool {
    do {
        let block = try currentBlock(at: path)
        let result: BlockOperationResult

        if [.bulletList, .numberedList, .checklist].contains(block.kind),
           block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = try BlockOperations.exitEmptyListBlock(in: document, at: path)
        } else {
            result = try BlockOperations.splitTextBlock(in: document, at: path, utf16Offset: utf16Offset)
        }

        document = result.document
        emitDocumentChange()
        if let focusPath = result.focusPath {
            focusBlock(at: focusPath)
        }
        return true
    } catch {
        return false
    }
}
```

Update `handleDeleteBackwardAtStart` to use `BlockOperations.deleteEmptyBlockBackward` first, then `BlockOperations.mergeBackward`.

- [ ] **Step 5: Run boundary tests and build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockOperationsTests test
xcodebuild build -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -derivedDataPath /tmp/CosmoOSBlockEditorDerivedData
```

Expected: tests PASS and build succeeds.

- [ ] **Step 6: Manual verification**

Verify:
- Return at the end of a paragraph creates a new paragraph below.
- Return in the middle of a paragraph splits it.
- Return in a heading creates a paragraph below.
- Return in an empty checklist exits to paragraph.
- Backspace at the start of a non-empty paragraph merges with the previous paragraph.
- Backspace in an empty block deletes it and focuses the previous block.

- [ ] **Step 7: Commit**

```bash
git add Editor/CosmoDocumentEditor.swift Editor/TextKitCoordinator.swift Editor/BlockEditor/BlockTextEditorRow.swift Editor/BlockEditor/BlockListView.swift Editor/BlockEditor/BlockOperations.swift Tests/CosmoOSTests/BlockOperationsTests.swift
git commit -m "feat: add block split and merge behavior"
```

---

## Task 8: Drag And Drop Reordering

**Files:**
- Create: `Editor/BlockEditor/BlockDropController.swift`
- Create: `Tests/CosmoOSTests/BlockDragDropTests.swift`
- Modify: `Editor/BlockEditor/BlockRowView.swift`
- Modify: `Editor/BlockEditor/BlockListView.swift`

- [ ] **Step 1: Write failing drag/drop tests**

Create `Tests/CosmoOSTests/BlockDragDropTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class BlockDragDropTests: XCTestCase {
    func testDropTargetAboveBlockUsesBlockIndex() {
        let target = BlockDropController.target(for: .above, path: .root(index: 2))
        XCTAssertEqual(target, BlockDropTarget(parent: nil, index: 2))
    }

    func testDropTargetBelowBlockUsesNextIndex() {
        let target = BlockDropController.target(for: .below, path: .root(index: 2))
        XCTAssertEqual(target, BlockDropTarget(parent: nil, index: 3))
    }

    func testNestedDropTargetPreservesParentPath() {
        let parent = BlockPath.root(index: 0)
        let child = parent.appendingChild(index: 1)

        let target = BlockDropController.target(for: .below, path: child)

        XCTAssertEqual(target, BlockDropTarget(parent: parent, index: 2))
    }
}
```

- [ ] **Step 2: Run failing drag/drop tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockDragDropTests test
```

Expected: FAIL with missing `BlockDropController`.

- [ ] **Step 3: Implement drop controller**

Create `Editor/BlockEditor/BlockDropController.swift`:

```swift
import Foundation

enum BlockDropPosition: String, Codable, Equatable, Hashable, Sendable {
    case above
    case below
}

struct BlockDragPayload: Codable, Equatable, Hashable, Sendable {
    var blockID: UUID
    var sourcePath: BlockPath
}

enum BlockDropController {
    static func target(for position: BlockDropPosition, path: BlockPath) -> BlockDropTarget {
        let insertionIndex: Int
        switch position {
        case .above:
            insertionIndex = path.indexInParent
        case .below:
            insertionIndex = path.indexInParent + 1
        }
        return BlockDropTarget(parent: path.parent, index: insertionIndex)
    }

    static func encodedPayload(_ payload: BlockDragPayload) -> Data {
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            assertionFailure("Failed to encode block drag payload: \(error)")
            return Data()
        }
    }

    static func decodedPayload(_ data: Data) -> BlockDragPayload? {
        try? JSONDecoder().decode(BlockDragPayload.self, from: data)
    }
}
```

- [ ] **Step 4: Add drag and drop affordances to rows**

Modify `BlockRowView`:

```swift
let dragPayload: BlockDragPayload
let onDropPayload: (BlockDragPayload, BlockDropPosition) -> Bool
```

Add to the row container:

```swift
.draggable(BlockDropController.encodedPayload(dragPayload))
.dropDestination(for: Data.self) { items, location in
    guard let data = items.first,
          let payload = BlockDropController.decodedPayload(data) else {
        return false
    }

    let position: BlockDropPosition = location.y < 24 ? .above : .below
    return onDropPayload(payload, position)
} isTargeted: { isTargeted in
    isHovering = isTargeted
}
```

Keep the visible drag handle as the only obvious drag affordance. If SwiftUI starts drags from the full row, wrap `.draggable` on the drag handle instead of the row.

- [ ] **Step 5: Move blocks from drops in `BlockListView`**

Add:

```swift
private func handleDrop(payload: BlockDragPayload, position: BlockDropPosition, destinationPath: BlockPath) -> Bool {
    do {
        let target = BlockDropController.target(for: position, path: destinationPath)
        let result = try BlockOperations.moveBlock(in: document, from: payload.sourcePath, to: target)
        document = result.document
        emitDocumentChange()
        if let focusPath = result.focusPath {
            focusBlock(at: focusPath)
        }
        return true
    } catch {
        return false
    }
}
```

Pass into each `BlockRowView`:

```swift
dragPayload: BlockDragPayload(blockID: block.id, sourcePath: path),
onDropPayload: { payload, position in
    handleDrop(payload: payload, position: position, destinationPath: path)
}
```

- [ ] **Step 6: Run drag/drop tests and build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/BlockDragDropTests -only-testing:CosmoOSTests/BlockOperationsTests test
xcodebuild build -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -derivedDataPath /tmp/CosmoOSBlockEditorDerivedData
```

Expected: tests PASS and build succeeds.

- [ ] **Step 7: Manual verification**

Verify:
- Hovering a block shows a small drag handle.
- Dragging the handle above another block shows an above indicator.
- Dragging below another block shows a below indicator.
- Dropping reorders the block and preserves its content.
- Dragging text inside a block still selects text rather than moving the block.

- [ ] **Step 8: Commit**

```bash
git add Editor/BlockEditor/BlockDropController.swift Editor/BlockEditor/BlockRowView.swift Editor/BlockEditor/BlockListView.swift Tests/CosmoOSTests/BlockDragDropTests.swift
git commit -m "feat: add block drag and drop reordering"
```

---

## Task 9: Content And Research Row Rendering

**Files:**
- Create: `Editor/BlockEditor/ContentBlockRowView.swift`
- Create: `Editor/BlockEditor/ResearchBlockRowView.swift`
- Modify: `Editor/BlockEditor/BlockListView.swift`

- [ ] **Step 1: Create content row**

Create `Editor/BlockEditor/ContentBlockRowView.swift`:

```swift
import AppKit
import SwiftUI

struct ContentBlockRowView: View {
    @Binding var block: RichBlock
    let path: BlockPath
    let focusCoordinator: BlockFocusCoordinator
    let fontSize: CGFloat
    let darkMode: Bool
    let overrideTextColor: NSColor?
    let editorTargetID: String?
    let navigationTargetID: UUID?
    let onSelectionChanged: ((EditorSelectionSnapshot) -> Void)?
    let onWritingAIRequest: (() -> Void)?
    let onBoundaryCommand: (EditorBoundaryCommand, BlockPath) -> Bool
    let onDocumentChange: () -> Void
    let onSlashRequest: (BlockSlashRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Label("Content", systemImage: "doc.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            BlockTextEditorRow(
                block: $block,
                path: path,
                focusCoordinator: focusCoordinator,
                fontSize: fontSize,
                placeholder: "Draft content...",
                darkMode: darkMode,
                overrideTextColor: overrideTextColor,
                allowSlashCommands: true,
                allowMentions: true,
                allowSelectionMenu: true,
                allowImages: true,
                typewriterMode: false,
                editorTargetID: editorTargetID,
                navigationTargetID: navigationTargetID,
                onSelectionChanged: onSelectionChanged,
                onWritingAIRequest: onWritingAIRequest,
                onBoundaryCommand: onBoundaryCommand,
                onDocumentChange: onDocumentChange,
                onSlashRequest: onSlashRequest
            )
        }
    }
}
```

- [ ] **Step 2: Create research row**

Create `Editor/BlockEditor/ResearchBlockRowView.swift`:

```swift
import AppKit
import SwiftUI

struct ResearchBlockRowView: View {
    @Binding var block: RichBlock
    let path: BlockPath
    let focusCoordinator: BlockFocusCoordinator
    let fontSize: CGFloat
    let darkMode: Bool
    let overrideTextColor: NSColor?
    let editorTargetID: String?
    let navigationTargetID: UUID?
    let onSelectionChanged: ((EditorSelectionSnapshot) -> Void)?
    let onWritingAIRequest: (() -> Void)?
    let onBoundaryCommand: (EditorBoundaryCommand, BlockPath) -> Bool
    let onDocumentChange: () -> Void
    let onSlashRequest: (BlockSlashRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Label("Research", systemImage: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            BlockTextEditorRow(
                block: $block,
                path: path,
                focusCoordinator: focusCoordinator,
                fontSize: fontSize,
                placeholder: "Collect sources and findings...",
                darkMode: darkMode,
                overrideTextColor: overrideTextColor,
                allowSlashCommands: true,
                allowMentions: true,
                allowSelectionMenu: true,
                allowImages: true,
                typewriterMode: false,
                editorTargetID: editorTargetID,
                navigationTargetID: navigationTargetID,
                onSelectionChanged: onSelectionChanged,
                onWritingAIRequest: onWritingAIRequest,
                onBoundaryCommand: onBoundaryCommand,
                onDocumentChange: onDocumentChange,
                onSlashRequest: onSlashRequest
            )
        }
    }
}
```

- [ ] **Step 3: Route block kinds to specialized rows**

In `BlockListView.blockRow(for:at:)`, before the generic text row branch, add:

```swift
if block.kind == .content, let binding = blockBinding(at: path) {
    ContentBlockRowView(
        block: binding,
        path: path,
        focusCoordinator: resolvedFocusCoordinator,
        fontSize: fontSize,
        darkMode: darkMode,
        overrideTextColor: overrideTextColor,
        editorTargetID: editorTargetID,
        navigationTargetID: navigationTargetID,
        onSelectionChanged: onSelectionChanged,
        onWritingAIRequest: onWritingAIRequest,
        onBoundaryCommand: handleBoundaryCommand,
        onDocumentChange: emitDocumentChange,
        onSlashRequest: handleSlashRequest
    )
} else if block.kind == .research, let binding = blockBinding(at: path) {
    ResearchBlockRowView(
        block: binding,
        path: path,
        focusCoordinator: resolvedFocusCoordinator,
        fontSize: fontSize,
        darkMode: darkMode,
        overrideTextColor: overrideTextColor,
        editorTargetID: editorTargetID,
        navigationTargetID: navigationTargetID,
        onSelectionChanged: onSelectionChanged,
        onWritingAIRequest: onWritingAIRequest,
        onBoundaryCommand: handleBoundaryCommand,
        onDocumentChange: emitDocumentChange,
        onSlashRequest: handleSlashRequest
    )
}
```

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild build -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -derivedDataPath /tmp/CosmoOSBlockEditorDerivedData
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Editor/BlockEditor/ContentBlockRowView.swift Editor/BlockEditor/ResearchBlockRowView.swift Editor/BlockEditor/BlockListView.swift
git commit -m "feat: add content and research block rows"
```

---

## Task 10: Polish, Accessibility, And Regression Pass

**Files:**
- Modify: `Editor/BlockEditor/BlockRowView.swift`
- Modify: `Editor/BlockEditor/BlockListView.swift`
- Modify: `Editor/SlashCommandMenu.swift`
- Modify: `Editor/TextKitCoordinator.swift`
- Modify: `Tests/CosmoOSTests/BlockOperationsTests.swift`
- Modify: `Tests/CosmoOSTests/BlockCommandCatalogTests.swift`
- Modify: `Tests/CosmoOSTests/BlockDragDropTests.swift`

- [ ] **Step 1: Add keyboard move commands**

In `BlockListView`, add commands for moving focused block:

```swift
private func moveFocusedBlock(delta: Int) -> Bool {
    guard let focusedID = resolvedFocusCoordinator.focusedBlockID,
          let sourcePath = resolvedFocusCoordinator.path(for: focusedID) else {
        return false
    }

    let destinationIndex = max(0, sourcePath.indexInParent + delta)
    let target = BlockDropTarget(parent: sourcePath.parent, index: destinationIndex)

    do {
        let result = try BlockOperations.moveBlock(in: document, from: sourcePath, to: target)
        document = result.document
        emitDocumentChange()
        if let focusPath = result.focusPath {
            focusBlock(at: focusPath)
        }
        return true
    } catch {
        return false
    }
}
```

Wire this to menu commands or local keyboard handling for Command-Control-Up and Command-Control-Down.

- [ ] **Step 2: Add accessibility labels**

Update `BlockRowView.dragHandle`:

```swift
.accessibilityLabel("Move block")
.accessibilityHint("Drag to reorder this block, or use keyboard move commands.")
```

Update drop indicators:

```swift
.accessibilityHidden(true)
```

- [ ] **Step 3: Remove legacy direct slash transformations**

In `TextKitCoordinator.swift`, remove direct command handlers that mutate headings, checklist prefixes, quote prefixes, divider text, and element scaffolds when the editor is hosted inside `BlockListView`. Keep legacy code only for non-block call sites that do not provide `onBlockSlashRequest`.

Search:

```bash
rg -n "applyHeading|toggleBlockPrefix|toggleChecklist|performSlashCommand|insertElement|divider" Editor/TextKitCoordinator.swift Editor/RichTextEditor.swift
```

Expected remaining direct transform code is guarded by the legacy non-block path.

- [ ] **Step 4: Full editor test run**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug \
  -only-testing:CosmoOSTests/BlockOperationsTests \
  -only-testing:CosmoOSTests/BlockCommandCatalogTests \
  -only-testing:CosmoOSTests/BlockDragDropTests \
  -only-testing:CosmoOSTests/RichDocumentTests \
  -only-testing:CosmoOSTests/RichDocumentHeadingTests \
  -only-testing:CosmoOSTests/DocumentElementStoreTests \
  test
```

Expected: all selected tests PASS.

- [ ] **Step 5: Full macOS build**

Run:

```bash
xcodebuild build -project CosmoOS.xcodeproj -scheme CosmoOS -destination 'platform=macOS' -derivedDataPath /tmp/CosmoOSBlockEditorDerivedData
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Manual verification matrix**

Verify in the app:
- `/h1`, `/h2`, `/h3` transform current block.
- `/todo`, `/bullet`, `/numbered`, `/quote` transform current block.
- `/divider`, `/image`, `/content`, `/research`, and Element commands replace an empty slash block or insert below a non-empty block.
- Return splits and creates blocks without the one-frame jump fixed previously.
- Backspace deletes empty blocks and merges non-empty text blocks.
- Hovering a block reveals the handle without shifting text.
- Dragging by the handle reorders blocks above and below.
- Text selection inside a block never starts a block drag.
- Nested Element child blocks still edit, split, and exit correctly.
- Sync/persistence saves the resulting document without changing unrelated atom metadata.

- [ ] **Step 7: Commit**

```bash
git add Editor/BlockEditor Editor/RichDocument.swift Editor/SlashCommandMenu.swift Editor/RichTextEditor.swift Editor/CosmoDocumentEditor.swift Editor/TextKitCoordinator.swift Tests/CosmoOSTests
git commit -m "polish: finalize notion-style block editor"
```

---

## Execution Notes

- Use `apply_patch` for all manual edits.
- Keep unrelated dirty worktree changes intact.
- Prefer pure XCTest coverage before UI wiring.
- Keep AppKit interop narrow: TextKit reports text and caret facts; SwiftUI applies block operations.
- If SwiftUI `.draggable` starts drags from the entire row, move `.draggable` onto the handle button so the row text remains selectable.

## Self-Review

- Spec coverage: slash transformations are covered by Tasks 4 and 6; content/research blocks by Tasks 2 and 9; split/merge by Task 7; drag/drop by Task 8; polish and accessibility by Task 10.
- Type consistency: `BlockPath`, `BlockDropTarget`, `BlockOperationResult`, `BlockCommand`, and `BlockSlashRequest` are introduced before later tasks use them.
- No direct TextKit block mutation remains in the block-editor path; TextKit remains responsible for typing, selection, and caret geometry.
- The plan uses incremental tests and commits so regressions can be isolated by task.
