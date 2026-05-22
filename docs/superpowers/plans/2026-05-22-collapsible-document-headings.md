# Collapsible Document Headings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shared collapsible Heading 1/2/3 sections to the rich-document editor, with Note Focus and Content Focus heading navigation.

**Architecture:** Store collapsed heading section blocks on the heading metadata while folded, using the same preservation pattern as Element children, so hidden content survives save/load and Return can create visible text below a folded section. Keep heading outline extraction, mutation, serializer restoration, and TextKit affordances in shared editor files; focus modes only render navigation.

**Tech Stack:** Swift, SwiftUI, AppKit TextKit, XCTest, existing `RichDocument`, `CosmoDocumentEditor`, `TextKitCoordinator`, `DS` design tokens.

---

## File Structure

- Modify `Editor/RichDocument.swift`: add `RichHeadingMetadata`, encode/decode it on `RichBlock`, include collapsed heading blocks in `plainText`, serialize heading IDs/collapse snapshots through attributed strings.
- Create `Editor/RichDocumentHeadings.swift`: pure heading outline, collapse/expand mutation, visible/folded block helpers, and editor decoration helpers.
- Modify `Editor/TextKitCoordinator.swift`: draw heading chevrons, hit-test them, toggle heading collapse, and handle Return on folded headings.
- Modify `Editor/CosmoDocumentEditor.swift`: expose heading outline and navigation callbacks from the shared editor wrapper.
- Modify `Editor/RichTextEditor.swift`: pass heading callbacks through to `TextKitEditorRepresentable`.
- Modify `UI/FocusMode/Notes/NoteFocusModeView.swift`: replace plain-text heading parsing with shared document outline and make `ON THIS NOTE` rows interactive.
- Modify `UI/FocusMode/Content/ContentFocusModeView.swift`: add a `SECTIONS` marginalia group and a compact popover entry point when marginalia rails are hidden.
- Create `Tests/CosmoOSTests/RichDocumentHeadingTests.swift`: pure model and serializer tests for heading folding.
- Modify `Tests/CosmoOSTests/FocusModeEditorBlurTests.swift`: add Note Focus heading extraction regression coverage beside existing Note Focus layout policy tests.
- Modify `Tests/CosmoOSTests/ContentFocusPaneLayoutPolicyTests.swift`: add Content Focus heading navigator visibility policy tests.

---

## Task 1: Heading Model And Pure Collapse Tests

**Files:**
- Create: `Tests/CosmoOSTests/RichDocumentHeadingTests.swift`
- Modify: `Editor/RichDocument.swift`
- Create: `Editor/RichDocumentHeadings.swift`

- [ ] **Step 1: Write failing model tests**

Create `Tests/CosmoOSTests/RichDocumentHeadingTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class RichDocumentHeadingTests: XCTestCase {
    func testOutlineExtractsNestedHeadingEntries() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [.text("Launch")]),
            .paragraph("Intro"),
            RichBlock(kind: .heading2, inlines: [.text("Draft")]),
            .paragraph("Body"),
            RichBlock(kind: .heading3, inlines: [.text("Hook")]),
            .paragraph("Hook copy"),
            RichBlock(kind: .heading2, inlines: [.text("Polish")])
        ])

        let outline = RichDocumentHeadings.outline(in: document)

        XCTAssertEqual(outline.map(\.level), [1, 2, 3, 2])
        XCTAssertEqual(outline.map(\.title), ["Launch", "Draft", "Hook", "Polish"])
        XCTAssertEqual(outline[0].parentID, nil)
        XCTAssertEqual(outline[1].parentID, outline[0].id)
        XCTAssertEqual(outline[2].parentID, outline[1].id)
        XCTAssertEqual(outline[3].parentID, outline[0].id)
    }

    func testCollapseMovesOwnedSectionIntoHeadingMetadata() throws {
        let document = RichDocument(blocks: [
            RichBlock(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, kind: .heading1, inlines: [.text("Launch")]),
            .paragraph("Intro"),
            RichBlock(kind: .heading2, inlines: [.text("Draft")]),
            .paragraph("Body"),
            RichBlock(kind: .heading1, inlines: [.text("Archive")])
        ])
        let headingID = try XCTUnwrap(document.blocks.first?.id)

        let collapsed = RichDocumentHeadings.toggledCollapse(headingID: headingID, in: document)

        XCTAssertEqual(collapsed.blocks.map(\.kind), [.heading1, .heading1])
        XCTAssertEqual(collapsed.blocks.first?.heading?.isCollapsed, true)
        XCTAssertEqual(collapsed.blocks.first?.heading?.collapsedBlocks.map(\.kind), [.paragraph, .heading2, .paragraph])
        XCTAssertEqual(collapsed.plainText, document.plainText)
    }

    func testExpandRestoresCollapsedBlocksAfterHeading() throws {
        let headingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let document = RichDocument(blocks: [
            RichBlock(
                id: headingID,
                kind: .heading1,
                inlines: [.text("Launch")],
                heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [
                    .paragraph("Intro"),
                    RichBlock(kind: .heading2, inlines: [.text("Draft")])
                ])
            ),
            RichBlock(kind: .heading1, inlines: [.text("Archive")])
        ])

        let expanded = RichDocumentHeadings.toggledCollapse(headingID: headingID, in: document)

        XCTAssertEqual(expanded.blocks.map(\.kind), [.heading1, .paragraph, .heading2, .heading1])
        XCTAssertEqual(expanded.blocks.first?.heading?.isCollapsed, false)
        XCTAssertEqual(expanded.blocks.first?.heading?.collapsedBlocks, [])
    }

    func testReturnBelowCollapsedHeadingInsertsVisibleParagraphOutsideHiddenBlocks() throws {
        let headingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let document = RichDocument(blocks: [
            RichBlock(
                id: headingID,
                kind: .heading1,
                inlines: [.text("Launch")],
                heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [
                    .paragraph("Hidden intro")
                ])
            ),
            RichBlock(kind: .heading1, inlines: [.text("Archive")])
        ])

        let inserted = RichDocumentHeadings.insertParagraphAfterCollapsedHeading(
            headingID: headingID,
            in: document
        )

        XCTAssertEqual(inserted.blocks.map(\.kind), [.heading1, .paragraph, .heading1])
        XCTAssertEqual(inserted.blocks[1].plainInlineText, "")
        XCTAssertEqual(inserted.blocks[0].heading?.collapsedBlocks.first?.plainInlineText, "Hidden intro")
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentHeadingTests test
```

Expected: FAIL with missing `RichDocumentHeadingTests`, `RichHeadingMetadata`, `RichDocumentHeadings`, `RichBlock.heading`, and `plainInlineText`.

- [ ] **Step 3: Add heading metadata to `RichDocument.swift`**

Add this near `RichBlockKind`:

```swift
struct RichHeadingMetadata: Codable, Equatable, Hashable, Sendable {
    var isCollapsed: Bool
    var collapsedBlocks: [RichBlock]

    init(isCollapsed: Bool = false, collapsedBlocks: [RichBlock] = []) {
        self.isCollapsed = isCollapsed
        self.collapsedBlocks = collapsedBlocks
    }
}
```

Update `RichBlock`:

```swift
struct RichBlock: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: RichBlockKind
    var inlines: [RichInlineNode] = []
    var checked: Bool? = nil
    var element: RichElementInstance? = nil
    var heading: RichHeadingMetadata? = nil
    var children: [RichBlock] = []

    init(
        id: UUID = UUID(),
        kind: RichBlockKind,
        inlines: [RichInlineNode] = [],
        checked: Bool? = nil,
        element: RichElementInstance? = nil,
        heading: RichHeadingMetadata? = nil,
        children: [RichBlock] = []
    ) {
        self.id = id
        self.kind = kind
        self.inlines = inlines
        self.checked = checked
        self.element = element
        self.heading = kind.headingLevelInt == nil ? nil : (heading ?? RichHeadingMetadata())
        self.children = children
    }
}
```

Add `heading` to `CodingKeys`, decode it with a heading default only for heading blocks, and encode it only for headings:

```swift
case heading
```

```swift
let decodedKind = try container.decode(RichBlockKind.self, forKey: .kind)
kind = decodedKind
heading = try container.decodeIfPresent(RichHeadingMetadata.self, forKey: .heading)
if decodedKind.headingLevelInt != nil, heading == nil {
    heading = RichHeadingMetadata()
}
```

```swift
if kind.headingLevelInt != nil {
    try container.encode(heading ?? RichHeadingMetadata(), forKey: .heading)
}
```

Add a block text helper:

```swift
extension RichBlock {
    var plainInlineText: String {
        inlines.map(\.plainText).joined()
    }
}
```

- [ ] **Step 4: Include collapsed heading blocks in `plainText`**

In `RichDocument.plainText(for:depth:)`, for heading cases, append collapsed metadata text after the heading line:

```swift
case .heading1:
    prefix = "# "
case .heading2:
    prefix = "## "
case .heading3:
    prefix = "### "
```

Then after computing `body`, before returning, add:

```swift
let line = indentation + prefix + body
if let collapsedBlocks = block.heading?.collapsedBlocks, !collapsedBlocks.isEmpty {
    let childText = plainText(for: collapsedBlocks, depth: depth + 1)
    return childText.isEmpty ? line : line + "\n" + childText
}
return line
```

- [ ] **Step 5: Add `Editor/RichDocumentHeadings.swift` implementation**

Create `Editor/RichDocumentHeadings.swift`:

```swift
import AppKit
import Foundation

struct RichHeadingOutlineEntry: Identifiable, Equatable {
    let id: UUID
    let level: Int
    let title: String
    let blockIndex: Int
    let parentID: UUID?
    let isCollapsed: Bool
    let hasCollapsedBlocks: Bool
}

enum RichDocumentHeadings {
    static func outline(in document: RichDocument) -> [RichHeadingOutlineEntry] {
        var stack: [(level: Int, id: UUID)] = []
        var entries: [RichHeadingOutlineEntry] = []

        for (index, block) in document.blocks.enumerated() {
            guard let level = block.kind.headingLevelInt else { continue }
            while let last = stack.last, last.level >= level {
                stack.removeLast()
            }
            let parentID = stack.last?.id
            let title = block.plainInlineText.trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(RichHeadingOutlineEntry(
                id: block.id,
                level: level,
                title: title.isEmpty ? "Untitled heading" : title,
                blockIndex: index,
                parentID: parentID,
                isCollapsed: block.heading?.isCollapsed ?? false,
                hasCollapsedBlocks: !(block.heading?.collapsedBlocks.isEmpty ?? true)
            ))
            stack.append((level, block.id))
        }

        return entries
    }

    static func toggledCollapse(headingID: UUID, in document: RichDocument) -> RichDocument {
        var blocks = document.blocks
        guard let index = blocks.firstIndex(where: { $0.id == headingID }),
              let level = blocks[index].kind.headingLevelInt else {
            return document
        }

        var heading = blocks[index]
        var metadata = heading.heading ?? RichHeadingMetadata()

        if metadata.isCollapsed {
            metadata.isCollapsed = false
            let restored = metadata.collapsedBlocks
            metadata.collapsedBlocks = []
            heading.heading = metadata
            blocks[index] = heading
            blocks.insert(contentsOf: restored, at: index + 1)
        } else {
            let end = sectionEndIndex(startingAt: index, level: level, in: blocks)
            let ownedRange = (index + 1)..<end
            metadata.isCollapsed = true
            metadata.collapsedBlocks = Array(blocks[ownedRange])
            heading.heading = metadata
            blocks[index] = heading
            blocks.removeSubrange(ownedRange)
        }

        return RichDocument(blocks: blocks)
    }

    static func insertParagraphAfterCollapsedHeading(headingID: UUID, in document: RichDocument) -> RichDocument {
        var blocks = document.blocks
        guard let index = blocks.firstIndex(where: { $0.id == headingID }),
              blocks[index].heading?.isCollapsed == true else {
            return document
        }
        blocks.insert(RichBlock(kind: .paragraph, inlines: [.text("")]), at: index + 1)
        return RichDocument(blocks: blocks)
    }

    static func sectionEndIndex(startingAt startIndex: Int, level: Int, in blocks: [RichBlock]) -> Int {
        var cursor = startIndex + 1
        while cursor < blocks.count {
            if let nextLevel = blocks[cursor].kind.headingLevelInt, nextLevel <= level {
                break
            }
            cursor += 1
        }
        return cursor
    }
}
```

- [ ] **Step 6: Run model tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentHeadingTests test
```

Expected: PASS for the first four `RichDocumentHeadingTests`.

- [ ] **Step 7: Commit Task 1**

```bash
git add Editor/RichDocument.swift Editor/RichDocumentHeadings.swift Tests/CosmoOSTests/RichDocumentHeadingTests.swift
git commit -m "feat: add rich document heading folding model"
```

---

## Task 2: Serializer Round Trip For Folded Headings

**Files:**
- Modify: `Tests/CosmoOSTests/RichDocumentHeadingTests.swift`
- Modify: `Editor/RichDocument.swift`
- Modify: `Editor/RichDocumentHeadings.swift`

- [ ] **Step 1: Add failing serializer tests**

Append to `RichDocumentHeadingTests`:

```swift
func testSerializerPreservesCollapsedHeadingBlocks() throws {
    let headingID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    let document = RichDocument(blocks: [
        RichBlock(
            id: headingID,
            kind: .heading1,
            inlines: [.text("Launch")],
            heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [
                .paragraph("Hidden intro"),
                RichBlock(kind: .heading2, inlines: [.text("Hidden subsection")])
            ])
        ),
        .paragraph("Visible below fold")
    ])

    let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 17, darkMode: false)
    let restored = RichDocumentSerializer.document(from: attributed)

    XCTAssertFalse(attributed.string.contains("Hidden intro"))
    XCTAssertEqual(restored, document)
    XCTAssertEqual(restored.plainText, document.plainText)
}

func testHeadingBlockIDsSurviveSerializerRoundTrip() throws {
    let headingID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    let document = RichDocument(blocks: [
        RichBlock(id: headingID, kind: .heading2, inlines: [.text("Stable")])
    ])

    let attributed = RichDocumentSerializer.attributedString(from: document)
    let restored = RichDocumentSerializer.document(from: attributed)

    XCTAssertEqual(restored.blocks.first?.id, headingID)
}
```

- [ ] **Step 2: Run failing serializer tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentHeadingTests/testSerializerPreservesCollapsedHeadingBlocks -only-testing:CosmoOSTests/RichDocumentHeadingTests/testHeadingBlockIDsSurviveSerializerRoundTrip test
```

Expected: FAIL because heading IDs and collapsed heading snapshots are not serialized.

- [ ] **Step 3: Add heading attributed-string keys**

In `RichDocumentAttributeKeys`, add:

```swift
static let headingBlockID = NSAttributedString.Key("CosmoHeadingBlockID")
static let headingCollapsed = NSAttributedString.Key("CosmoHeadingCollapsed")
static let headingCollapsedChildrenJSON = NSAttributedString.Key("CosmoHeadingCollapsedChildrenJSON")
```

- [ ] **Step 4: Serialize heading metadata**

In `RichDocumentSerializer.inlineAttributes(...)`, when `headingLevel` is present, add:

```swift
attributes[RichDocumentAttributeKeys.headingBlockID] = block.id.uuidString
attributes[RichDocumentAttributeKeys.headingCollapsed] = NSNumber(value: block.heading?.isCollapsed ?? false)
if let collapsedBlocks = block.heading?.collapsedBlocks, !collapsedBlocks.isEmpty,
   let data = try? JSONEncoder().encode(collapsedBlocks),
   let json = String(data: data, encoding: .utf8) {
    attributes[RichDocumentAttributeKeys.headingCollapsedChildrenJSON] = json
}
```

- [ ] **Step 5: Decode heading metadata**

In `RichDocumentSerializer.block(from:)`, replace the heading detection block with:

```swift
if line.length > 0,
   let level = intAttribute(RichDocumentAttributeKeys.headingLevel, in: line) {
    let kind: RichBlockKind = level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3
    let id = uuidAttribute(RichDocumentAttributeKeys.headingBlockID, in: line) ?? UUID()
    let collapsed = boolAttribute(RichDocumentAttributeKeys.headingCollapsed, in: line) ?? false
    let collapsedBlocks = headingCollapsedBlocksAttribute(from: line)
    return RichBlock(
        id: id,
        kind: kind,
        inlines: inlineNodes(from: line),
        heading: RichHeadingMetadata(isCollapsed: collapsed, collapsedBlocks: collapsedBlocks)
    )
}
```

Add helper near `elementChildrenAttribute(from:)`:

```swift
private static func headingCollapsedBlocksAttribute(from line: NSAttributedString) -> [RichBlock] {
    guard let json = stringAttribute(RichDocumentAttributeKeys.headingCollapsedChildrenJSON, in: line),
          let data = json.data(using: .utf8),
          let blocks = try? JSONDecoder().decode([RichBlock].self, from: data) else {
        return []
    }
    return blocks
}
```

- [ ] **Step 6: Omit hidden folded heading blocks from attributed output**

In `RichDocumentSerializer.attributedString(from:depth:...)`, no extra skip logic is needed for folded blocks because Task 1 stores them in `heading.collapsedBlocks` instead of `document.blocks`. Confirm the loop renders the collapsed heading line and visible sibling blocks only.

- [ ] **Step 7: Run serializer tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentHeadingTests test
```

Expected: PASS for `RichDocumentHeadingTests`.

- [ ] **Step 8: Run existing rich document tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentTests test
```

Expected: PASS for existing Element, title, metadata, and mention tests.

- [ ] **Step 9: Commit Task 2**

```bash
git add Editor/RichDocument.swift Editor/RichDocumentHeadings.swift Tests/CosmoOSTests/RichDocumentHeadingTests.swift
git commit -m "feat: preserve folded headings through rich document serialization"
```

---

## Task 3: TextKit Heading Chevron And Return Behavior

**Files:**
- Modify: `Tests/CosmoOSTests/RichDocumentHeadingTests.swift`
- Modify: `Editor/RichDocumentHeadings.swift`
- Modify: `Editor/TextKitCoordinator.swift`

- [ ] **Step 1: Add decoration tests**

Append to `RichDocumentHeadingTests`:

```swift
func testHeadingEditorDecorationFindsCollapsedHeadingLine() throws {
    let headingID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    let document = RichDocument(blocks: [
        RichBlock(
            id: headingID,
            kind: .heading1,
            inlines: [.text("Launch")],
            heading: RichHeadingMetadata(isCollapsed: true, collapsedBlocks: [.paragraph("Hidden")])
        )
    ])
    let attributed = RichDocumentSerializer.attributedString(from: document)

    let decorations = RichHeadingEditorDecoration.decorations(in: attributed)

    XCTAssertEqual(decorations.count, 1)
    XCTAssertEqual(decorations.first?.id, headingID)
    XCTAssertEqual(decorations.first?.level, 1)
    XCTAssertEqual(decorations.first?.isCollapsed, true)
    XCTAssertEqual(decorations.first?.title, "Launch")
}
```

- [ ] **Step 2: Run failing decoration test**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentHeadingTests/testHeadingEditorDecorationFindsCollapsedHeadingLine test
```

Expected: FAIL because `RichHeadingEditorDecoration` does not exist.

- [ ] **Step 3: Add heading editor decoration helper**

Append to `Editor/RichDocumentHeadings.swift`:

```swift
struct RichHeadingEditorDecoration: Equatable {
    let range: NSRange
    let id: UUID
    let level: Int
    let title: String
    let isCollapsed: Bool
    let hasCollapsedBlocks: Bool

    static func decorations(in attributedString: NSAttributedString) -> [RichHeadingEditorDecoration] {
        guard attributedString.length > 0 else { return [] }
        let fullString = attributedString.string as NSString
        var lineStart = 0
        var output: [RichHeadingEditorDecoration] = []

        while lineStart < attributedString.length {
            let lineRange = fullString.lineRange(for: NSRange(location: lineStart, length: 0))
            let safeRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: attributedString.length))
            let trimmedRange = trimmingTrailingNewline(from: safeRange, in: fullString)

            if trimmedRange.length > 0,
               let level = intValue(attributedString.attribute(RichDocumentAttributeKeys.headingLevel, at: trimmedRange.location, effectiveRange: nil)),
               let id = uuidValue(attributedString.attribute(RichDocumentAttributeKeys.headingBlockID, at: trimmedRange.location, effectiveRange: nil)) {
                let collapsed = boolValue(attributedString.attribute(RichDocumentAttributeKeys.headingCollapsed, at: trimmedRange.location, effectiveRange: nil)) ?? false
                let hiddenJSON = attributedString.attribute(RichDocumentAttributeKeys.headingCollapsedChildrenJSON, at: trimmedRange.location, effectiveRange: nil) as? String
                output.append(RichHeadingEditorDecoration(
                    range: trimmedRange,
                    id: id,
                    level: level,
                    title: fullString.substring(with: trimmedRange).trimmingCharacters(in: .whitespacesAndNewlines),
                    isCollapsed: collapsed,
                    hasCollapsedBlocks: !(hiddenJSON ?? "").isEmpty
                ))
            }

            lineStart = lineRange.location + lineRange.length
            if lineStart <= safeRange.location { break }
        }

        return output
    }

    private static func trimmingTrailingNewline(from range: NSRange, in string: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let character = string.substring(with: NSRange(location: range.location + length - 1, length: 1))
            if character == "\n" || character == "\r" {
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: range.location, length: length)
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func uuidValue(_ value: Any?) -> UUID? {
        if let value = value as? UUID { return value }
        if let value = value as? String { return UUID(uuidString: value) }
        return nil
    }
}
```

- [ ] **Step 4: Draw heading chevrons in `CosmoTextView`**

In `CosmoTextView`, add:

```swift
var onToggleHeadingCollapse: ((UUID) -> Void)?
```

Change `draw(_:)`:

```swift
override func draw(_ dirtyRect: NSRect) {
    drawHeadingDecorations(in: dirtyRect)
    drawElementBlockDecorations(in: dirtyRect)
    super.draw(dirtyRect)
}
```

Add a `HeadingHit` type and drawing/hit-test methods:

```swift
private struct HeadingHit {
    let id: UUID
}

private func drawHeadingDecorations(in dirtyRect: NSRect) {
    guard let storage = textStorage,
          storage.length > 0,
          let layoutManager,
          let textContainer else { return }

    let decorations = RichHeadingEditorDecoration.decorations(in: storage)
    guard !decorations.isEmpty else { return }
    layoutManager.ensureLayout(for: textContainer)

    for decoration in decorations where decoration.hasCollapsedBlocks || decoration.isCollapsed {
        guard let rect = headingChevronRect(for: decoration, storageLength: storage.length),
              rect.intersects(dirtyRect.insetBy(dx: -8, dy: -8)) else { continue }
        drawHeadingChevron(collapsed: decoration.isCollapsed, in: rect, color: elementBlockSecondaryColor)
    }
}

private func headingHitTest(at point: NSPoint) -> HeadingHit? {
    guard let storage = textStorage,
          storage.length > 0,
          let layoutManager,
          let textContainer else { return nil }
    layoutManager.ensureLayout(for: textContainer)

    for decoration in RichHeadingEditorDecoration.decorations(in: storage).reversed() {
        guard decoration.hasCollapsedBlocks || decoration.isCollapsed,
              let rect = headingChevronRect(for: decoration, storageLength: storage.length) else { continue }
        if rect.insetBy(dx: -6, dy: -6).contains(point) {
            return HeadingHit(id: decoration.id)
        }
    }
    return nil
}

private func headingChevronRect(for decoration: RichHeadingEditorDecoration, storageLength: Int) -> NSRect? {
    guard let layoutManager, let textContainer else { return nil }
    let characterRange = NSIntersectionRange(decoration.range, NSRange(location: 0, length: storageLength))
    guard characterRange.length > 0 else { return nil }
    let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
    let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    guard glyphRect.height.isFinite, glyphRect.height > 0 else { return nil }
    let size: CGFloat = 9
    return NSRect(
        x: textContainerOrigin.x - 18 + CGFloat(decoration.level - 1) * 2,
        y: textContainerOrigin.y + glyphRect.midY - size / 2,
        width: size,
        height: size
    )
}
```

Reuse the existing `drawElementChevron(collapsed:in:color:)` by making it generic enough for headings, or add `drawHeadingChevron` with the same path logic.

- [ ] **Step 5: Hit-test heading chevrons**

In `CosmoTextView.mouseDown(with:)`, before the element hit test, add:

```swift
if let hit = headingHitTest(at: localPoint) {
    onToggleHeadingCollapse?(hit.id)
    return
}
```

In `TextKitEditorRepresentable.configureTextView`, wire:

```swift
textView.onToggleHeadingCollapse = { [weak coordinator = context.coordinator] headingID in
    guard let coordinator, let textView = coordinator.textViewReference else { return }
    coordinator.toggleHeadingCollapse(headingID: headingID, in: textView)
}
```

- [ ] **Step 6: Add coordinator toggle and Return behavior**

In `Coordinator`, add:

```swift
func toggleHeadingCollapse(headingID: UUID, in textView: NSTextView) {
    guard let storage = textView.textStorage else { return }
    let selectedRange = textView.selectedRange()
    let document = RichDocumentSerializer.document(from: storage)
    let updated = RichDocumentHeadings.toggledCollapse(headingID: headingID, in: document)
    guard updated != document else { return }

    let serialized = RichDocumentSerializer.attributedString(
        from: updated,
        fontSize: parent.fontSize,
        darkMode: parent.darkMode,
        singleLine: parent.singleLine,
        baseFontWeight: parent.baseFontWeight,
        titleMode: parent.titleConfiguration != nil
    )
    storage.setAttributedString(serialized)
    textView.setSelectedRange(NSRange(location: min(selectedRange.location, storage.length), length: 0))
    resetToNormalTypingAttributes(textView)
    syncBindings(from: textView)
    notifyContentHeightChange(for: textView)
}
```

Before the default Return insertion in `textView(_:doCommandBy:)`, add:

```swift
if let headingID = collapsedHeadingIDOnCurrentLine(in: textView) {
    let document = RichDocumentSerializer.document(from: textView.attributedString())
    let updated = RichDocumentHeadings.insertParagraphAfterCollapsedHeading(headingID: headingID, in: document)
    let serialized = RichDocumentSerializer.attributedString(
        from: updated,
        fontSize: parent.fontSize,
        darkMode: parent.darkMode,
        singleLine: parent.singleLine,
        baseFontWeight: parent.baseFontWeight,
        titleMode: parent.titleConfiguration != nil
    )
    textView.textStorage?.setAttributedString(serialized)
    if let newParagraphRange = rangeOfParagraphAfterHeading(headingID: headingID, in: textView.attributedString()) {
        textView.setSelectedRange(NSRange(location: newParagraphRange.location, length: 0))
    }
    resetToNormalTypingAttributes(textView)
    syncBindings(from: textView)
    notifyContentHeightChange(for: textView)
    return true
}
```

Implement `collapsedHeadingIDOnCurrentLine(in:)` by reading `headingBlockID` and `headingCollapsed` from the first character of the current line, and implement `rangeOfParagraphAfterHeading(headingID:in:)` by scanning line ranges until the first line after the matching heading.

- [ ] **Step 7: Run focused tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentHeadingTests test
```

Expected: PASS for heading model, serializer, and decoration tests.

- [ ] **Step 8: Build app target**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 9: Commit Task 3**

```bash
git add Editor/RichDocumentHeadings.swift Editor/TextKitCoordinator.swift Tests/CosmoOSTests/RichDocumentHeadingTests.swift
git commit -m "feat: add editor controls for folded headings"
```

---

## Task 4: Shared Editor Navigation Hooks

**Files:**
- Modify: `Editor/CosmoDocumentEditor.swift`
- Modify: `Editor/RichTextEditor.swift`
- Modify: `Editor/TextKitCoordinator.swift`

- [ ] **Step 1: Add editor hook types**

In `Editor/RichDocumentHeadings.swift`, add:

```swift
struct RichHeadingNavigationAction: Equatable {
    let scrollToHeadingID: UUID?
    let toggleHeadingID: UUID?

    static func scroll(to id: UUID) -> RichHeadingNavigationAction {
        RichHeadingNavigationAction(scrollToHeadingID: id, toggleHeadingID: nil)
    }

    static func toggle(_ id: UUID) -> RichHeadingNavigationAction {
        RichHeadingNavigationAction(scrollToHeadingID: nil, toggleHeadingID: id)
    }
}
```

- [ ] **Step 2: Add bindings to `CosmoDocumentEditor`**

Add properties:

```swift
var onHeadingOutlineChange: (([RichHeadingOutlineEntry]) -> Void)? = nil
var headingNavigationAction: RichHeadingNavigationAction? = nil
```

Pass both into `RichTextEditor`.

In `syncEditorFromDocument()` and `syncDocumentFromEditor()` after resolving `RichDocument`, call:

```swift
onHeadingOutlineChange?(RichDocumentHeadings.outline(in: resolved))
```

and:

```swift
onHeadingOutlineChange?(RichDocumentHeadings.outline(in: updated))
```

- [ ] **Step 3: Pass hooks through `RichTextEditor`**

Add the same properties to `RichTextEditor` and its initializer, then pass `headingNavigationAction` to `TextKitEditorRepresentable`.

- [ ] **Step 4: Support navigation action in `TextKitEditorRepresentable`**

Add:

```swift
var headingNavigationAction: RichHeadingNavigationAction? = nil
```

In `updateNSView`, after applying storage overrides, add:

```swift
if let action = headingNavigationAction {
    context.coordinator.performHeadingNavigationAction(action, in: textView)
}
```

In `Coordinator`, implement:

```swift
func performHeadingNavigationAction(_ action: RichHeadingNavigationAction, in textView: NSTextView) {
    if let id = action.toggleHeadingID {
        toggleHeadingCollapse(headingID: id, in: textView)
    }
    if let id = action.scrollToHeadingID,
       let range = headingRange(headingID: id, in: textView.attributedString()) {
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
        textView.scrollRangeToVisible(range)
        parent.onSelectionChange?(selectionSnapshot(in: textView))
    }
}
```

Implement `headingRange(headingID:in:)` by scanning `RichHeadingEditorDecoration.decorations(in:)`.

- [ ] **Step 5: Run build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit Task 4**

```bash
git add Editor/CosmoDocumentEditor.swift Editor/RichTextEditor.swift Editor/TextKitCoordinator.swift Editor/RichDocumentHeadings.swift
git commit -m "feat: expose heading navigation from document editor"
```

---

## Task 5: Note Focus Heading Navigator

**Files:**
- Modify: `Tests/CosmoOSTests/FocusModeEditorBlurTests.swift`
- Modify: `UI/FocusMode/Notes/NoteFocusModeView.swift`

- [ ] **Step 1: Add Note Focus policy test**

Append to `NoteFocusHeaderLayoutPolicyTests`:

```swift
func testNoteFocusUsesSharedHeadingOutlineEntries() {
    let document = RichDocument(blocks: [
        RichBlock(kind: .heading1, inlines: [.text("Launch")]),
        RichBlock(kind: .heading2, inlines: [.text("Draft")])
    ])

    let entries = RichDocumentHeadings.outline(in: document)

    XCTAssertEqual(entries.map(\.title), ["Launch", "Draft"])
    XCTAssertEqual(entries.map(\.level), [1, 2])
}
```

- [ ] **Step 2: Run focused Note Focus test**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/NoteFocusHeaderLayoutPolicyTests/testNoteFocusUsesSharedHeadingOutlineEntries test
```

Expected: PASS once Task 1 exists.

- [ ] **Step 3: Replace Note Focus heading state**

In `NoteFocusModeView`, replace:

```swift
@State private var contentHeadings: [NoteHeadingEntry] = []
```

with:

```swift
@State private var contentHeadings: [RichHeadingOutlineEntry] = []
@State private var headingNavigationAction: RichHeadingNavigationAction?
```

Delete the `NoteHeadingEntry` struct at the bottom of the file after all usages are updated.

- [ ] **Step 4: Wire editor heading outline changes**

In the body `CosmoDocumentEditor`, add:

```swift
headingNavigationAction: headingNavigationAction,
onHeadingOutlineChange: { entries in
    contentHeadings = entries
}
```

Remove the `refreshHeadings()` call from `onDocumentChange`.

- [ ] **Step 5: Make outline rows interactive**

Replace `outlineEntryRow(_:)` with:

```swift
private func outlineEntryRow(_ entry: RichHeadingOutlineEntry) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
        Button {
            headingNavigationAction = .toggle(entry.id)
        } label: {
            Image(systemName: entry.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(entry.hasCollapsedBlocks || entry.isCollapsed ? DS.gilt.opacity(0.7) : DS.documentTextMuted.opacity(0.5))
                .frame(width: 12, height: 16)
        }
        .buttonStyle(.plain)
        .disabled(!entry.hasCollapsedBlocks && !entry.isCollapsed)
        .help(entry.isCollapsed ? "Expand section" : "Collapse section")

        Button {
            headingNavigationAction = .scroll(to: entry.id)
        } label: {
            Text(entry.title)
                .font(entry.level == 1 ? DS.subheadline : DS.caption)
                .foregroundStyle(entry.level == 1 ? DS.documentText : DS.documentTextSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
    .padding(.leading, CGFloat(entry.level - 1) * DS.space8)
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

- [ ] **Step 6: Remove old parser**

Delete `refreshHeadings()` from `NoteFocusModeView`.

- [ ] **Step 7: Run Note Focus and heading tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/NoteFocusHeaderLayoutPolicyTests -only-testing:CosmoOSTests/RichDocumentHeadingTests test
```

Expected: PASS.

- [ ] **Step 8: Commit Task 5**

```bash
git add UI/FocusMode/Notes/NoteFocusModeView.swift Tests/CosmoOSTests/FocusModeEditorBlurTests.swift
git commit -m "feat: navigate folded headings in note focus"
```

---

## Task 6: Content Focus Heading Navigator

**Files:**
- Modify: `Tests/CosmoOSTests/ContentFocusPaneLayoutPolicyTests.swift`
- Modify: `UI/FocusMode/Content/ContentFocusModeView.swift`

- [ ] **Step 1: Add Content Focus policy tests**

Add to `ContentFocusPaneLayoutPolicyTests`:

```swift
func testContentFocusShowsHeadingMarginaliaOnlyWhenRailsVisibleAndHeadingsExist() {
    XCTAssertTrue(ContentFocusLayoutPolicy.showsHeadingMarginalia(
        hasHeadings: true,
        showsMarginaliaRails: true
    ))
    XCTAssertFalse(ContentFocusLayoutPolicy.showsHeadingMarginalia(
        hasHeadings: false,
        showsMarginaliaRails: true
    ))
    XCTAssertFalse(ContentFocusLayoutPolicy.showsHeadingMarginalia(
        hasHeadings: true,
        showsMarginaliaRails: false
    ))
}

func testContentFocusShowsHeadingPopoverWhenHeadingsExistAndRailsAreHidden() {
    XCTAssertTrue(ContentFocusLayoutPolicy.showsHeadingPopoverButton(
        hasHeadings: true,
        showsMarginaliaRails: false
    ))
    XCTAssertFalse(ContentFocusLayoutPolicy.showsHeadingPopoverButton(
        hasHeadings: true,
        showsMarginaliaRails: true
    ))
    XCTAssertFalse(ContentFocusLayoutPolicy.showsHeadingPopoverButton(
        hasHeadings: false,
        showsMarginaliaRails: false
    ))
}
```

- [ ] **Step 2: Run failing policy tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/ContentFocusPaneLayoutPolicyTests/testContentFocusShowsHeadingMarginaliaOnlyWhenRailsVisibleAndHeadingsExist -only-testing:CosmoOSTests/ContentFocusPaneLayoutPolicyTests/testContentFocusShowsHeadingPopoverWhenHeadingsExistAndRailsAreHidden test
```

Expected: FAIL because the new policy functions do not exist.

- [ ] **Step 3: Add Content Focus policy helpers**

In `ContentFocusLayoutPolicy`, add:

```swift
static func showsHeadingMarginalia(hasHeadings: Bool, showsMarginaliaRails: Bool) -> Bool {
    hasHeadings && showsMarginaliaRails
}

static func showsHeadingPopoverButton(hasHeadings: Bool, showsMarginaliaRails: Bool) -> Bool {
    hasHeadings && !showsMarginaliaRails
}
```

- [ ] **Step 4: Add heading state to Content Focus**

In `ContentFocusModeView`, add:

```swift
@State private var draftHeadings: [RichHeadingOutlineEntry] = []
@State private var headingNavigationAction: RichHeadingNavigationAction?
@State private var showHeadingPopover = false
@State private var showsCurrentMarginaliaRails = false
```

- [ ] **Step 5: Wire editor heading callbacks**

In the draft `CosmoDocumentEditor`, add:

```swift
headingNavigationAction: headingNavigationAction,
onHeadingOutlineChange: { entries in
    draftHeadings = entries
}
```

- [ ] **Step 6: Track marginalia visibility**

Inside `scriptoriumBody`, after computing `showMarginaliaRails`, add:

```swift
Color.clear
    .frame(width: 0, height: 0)
    .onAppear { showsCurrentMarginaliaRails = showMarginaliaRails }
    .onChange(of: showMarginaliaRails) { _, newValue in
        showsCurrentMarginaliaRails = newValue
    }
```

Place it inside the `ZStack` so it does not affect layout.

- [ ] **Step 7: Add `SECTIONS` marginalia group**

In `scriptoriumLeftMargin`, insert this before `outlineMarginaliaSection`:

```swift
if ContentFocusLayoutPolicy.showsHeadingMarginalia(
    hasHeadings: !draftHeadings.isEmpty,
    showsMarginaliaRails: true
) {
    headingMarginaliaSection
}
```

Add:

```swift
private var headingMarginaliaSection: some View {
    VStack(alignment: .leading, spacing: DS.space10) {
        MarginaliaLabel("SECTIONS", countText: "\(draftHeadings.count)")
        ForEach(draftHeadings) { entry in
            contentHeadingRow(entry)
        }
    }
}

private func contentHeadingRow(_ entry: RichHeadingOutlineEntry) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
        Button {
            headingNavigationAction = .toggle(entry.id)
        } label: {
            Image(systemName: entry.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(DS.giltMuted)
                .frame(width: 12, height: 14)
        }
        .buttonStyle(.plain)
        .disabled(!entry.hasCollapsedBlocks && !entry.isCollapsed)

        Button {
            headingNavigationAction = .scroll(to: entry.id)
        } label: {
            Text(entry.title)
                .font(entry.level == 1 ? DS.callout : DS.caption)
                .foregroundStyle(entry.level == 1 ? DS.documentText : DS.inkFaded)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
    .padding(.leading, CGFloat(entry.level - 1) * DS.space8)
}
```

- [ ] **Step 8: Add compact popover button**

Near `wordCharCounter` in the editor overlay `ZStack`, add:

```swift
if ContentFocusLayoutPolicy.showsHeadingPopoverButton(
    hasHeadings: !draftHeadings.isEmpty,
    showsMarginaliaRails: showsCurrentMarginaliaRails
) {
    headingPopoverButton
}
```

Add:

```swift
private var headingPopoverButton: some View {
    VStack {
        Spacer()
        HStack {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    showHeadingPopover.toggle()
                }
            } label: {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.inkFaded)
                    .frame(width: 28, height: 28)
                    .background(DS.glassCardFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.glassBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Show sections")
            Spacer()
        }
        .padding(.leading, DS.space20)
        .padding(.bottom, DS.space52)
    }
    .overlay(alignment: .bottomLeading) {
        if showHeadingPopover {
            VStack(alignment: .leading, spacing: DS.space8) {
                ForEach(draftHeadings) { entry in
                    contentHeadingRow(entry)
                }
            }
            .padding(DS.space12)
            .frame(width: 240, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.glassBorder, lineWidth: 0.5))
            .padding(.leading, DS.space20)
            .padding(.bottom, DS.space88)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
        }
    }
}
```

- [ ] **Step 9: Run Content Focus policy tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/ContentFocusPaneLayoutPolicyTests test
```

Expected: PASS.

- [ ] **Step 10: Build app target**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 11: Commit Task 6**

```bash
git add UI/FocusMode/Content/ContentFocusModeView.swift Tests/CosmoOSTests/ContentFocusPaneLayoutPolicyTests.swift
git commit -m "feat: navigate folded headings in content focus"
```

---

## Task 7: Final Verification And Polish

**Files:**
- Inspect only unless verification reveals a defect:
  - `Editor/RichDocument.swift`
  - `Editor/RichDocumentHeadings.swift`
  - `Editor/TextKitCoordinator.swift`
  - `Editor/CosmoDocumentEditor.swift`
  - `Editor/RichTextEditor.swift`
  - `UI/FocusMode/Notes/NoteFocusModeView.swift`
  - `UI/FocusMode/Content/ContentFocusModeView.swift`

- [ ] **Step 1: Run whitespace and diff checks**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Run focused test suite**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/RichDocumentHeadingTests -only-testing:CosmoOSTests/RichDocumentTests -only-testing:CosmoOSTests/NoteFocusHeaderLayoutPolicyTests -only-testing:CosmoOSTests/ContentFocusPaneLayoutPolicyTests test
```

Expected: PASS.

- [ ] **Step 3: Run full app test command**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug test
```

Expected: PASS. If unrelated existing tests fail, capture the failing test names and rerun the focused suite to confirm this feature's tests still pass.

- [ ] **Step 4: Manual smoke checklist**

Run the app in Xcode or with the repo's existing build/run workflow, then verify:

```text
1. Open Note Focus Mode.
2. Type / Heading 1 and write "Launch".
3. Add a paragraph below it.
4. Click the heading chevron.
5. Confirm the paragraph disappears and the left ON THIS NOTE rail shows the collapsed state.
6. Press Return on the collapsed heading.
7. Confirm a visible blank paragraph appears below the collapsed heading.
8. Close and reopen the note.
9. Confirm collapsed state and hidden content persist.
10. Repeat Heading 1/2/3 navigation in Content Focus Mode.
```

- [ ] **Step 5: Final commit if verification changed files**

If Task 7 required code changes:

```bash
git add Editor UI Tests
git commit -m "fix: polish folded heading behavior"
```

If Task 7 only verified existing commits, do not create an empty commit.

---

## Self-Review Checklist

- Spec coverage: The plan covers shared heading state, nested H1/H2/H3 ranges, persisted hidden content, Return below collapsed heading, Note Focus rail navigation, Content Focus non-overlapping navigation, and regression tests.
- Red-flag scan: The plan contains no incomplete markers, vague deferred work, or undefined task references.
- Type consistency: The plan consistently uses `RichHeadingMetadata`, `RichHeadingOutlineEntry`, `RichDocumentHeadings`, `RichHeadingEditorDecoration`, and `RichHeadingNavigationAction`.
- Risk focus: The highest-risk invariant is hidden content preservation; Task 2 tests serializer round trip and `plainText` equality before UI work starts.
