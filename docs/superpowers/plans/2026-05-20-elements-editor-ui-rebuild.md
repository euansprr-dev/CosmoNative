# Elements Editor UI Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the in-editor Element header so it is visually polished, interactive, correctly themed, and semantically matches the reference: chevron, valid icon, muted Element name label, optional block title, thin outline, and reliable collapse/expand.

**Architecture:** Keep `RichDocument` as the source of truth, but stop treating Element chrome as passive decoration only. Add a small AppKit bridge layer around the existing `NSTextView`: one pure layout helper computes header rects for drawing and hit testing, one mutation helper toggles `RichDocument` collapse state by instance id, and TextKit only handles the imperative click/draw boundary.

**Tech Stack:** Swift, SwiftUI, AppKit/TextKit, existing `RichDocument` serializer, existing `DS` theme tokens, XCTest.

---

## Root Cause Summary

The current Element header is broken for four reasons:

1. `CosmoTextView.draw(_:)` draws a chevron and icon, but they are not real controls and no hit testing routes clicks to collapse/expand.
2. The header label is hardcoded to `"Element"` instead of using the user-created Element name such as `"Concept"`.
3. The right-side text uses the editor’s large semibold document text styling, so it reads like a title instead of quiet row metadata.
4. SF Symbols are drawn stretched into a rect and invalid symbol names are not validated, causing boxes or distorted icons.

## Target UI

```text
Collapsed
┌──────────────────────────────────────────────────────────────┐
│  ›  ◌  Concept        Audience Situation                     │
└──────────────────────────────────────────────────────────────┘

Expanded
┌──────────────────────────────────────────────────────────────┐
│  ˅  ◌  Concept        Audience Situation                     │
│                                                              │
│     Nested editor content lives inside the same outline      │
└──────────────────────────────────────────────────────────────┘
```

Rules:
- `Concept` is the Element definition name the user created.
- `Audience Situation` is the block instance title, editable as normal text.
- If there is no instance title yet, insert `Untitled` selected so the user can type over it.
- The chevron must toggle collapse/expand; the whole 28pt leading control area should be clickable.
- Collapsed visual state hides children in the editor, but children remain persisted and available to AI context.
- Light theme: white fill, thin cool outline.
- Dark theme: dark surface fill, thin low-contrast outline.

## File Structure

- Modify `Editor/DocumentElements.swift`
  - Add header layout structs used by both drawing and hit testing.
  - Add symbol validation/rendering helpers.
  - Add pure collapse mutation helper for `RichDocument`.
- Modify `Editor/RichDocument.swift`
  - Split Element definition label from editable instance title in attributes.
  - Render header string as the instance title only.
  - Keep collapsed children in serialized metadata.
- Modify `Editor/TextKitCoordinator.swift`
  - Replace ad hoc Element drawing math with shared layout helper.
  - Add hit testing in `CosmoTextView.mouseDown(with:)`.
  - Wire a narrow `onToggleElementCollapse(UUID)` callback into the coordinator.
- Modify `Editor/CosmoDocumentRenderer.swift`
  - Match read-only SwiftUI rendering to the same visual hierarchy.
- Modify `Editor/SlashCommandMenu.swift`
  - Keep only valid SF Symbol values for new Elements.
- Modify `Tests/CosmoOSTests/RichDocumentTests.swift`
  - Add serializer and collapse tests for the new label/title split.
- Create `Tests/CosmoOSTests/DocumentElementHeaderLayoutTests.swift`
  - Test hit target and layout math without relying on screenshots.

---

## Task 1: Lock The Semantics With Failing Tests

**Files:**
- Modify: `Tests/CosmoOSTests/RichDocumentTests.swift`
- Create: `Tests/CosmoOSTests/DocumentElementHeaderLayoutTests.swift`

- [ ] **Step 1: Add tests for Element name versus instance title**

Add these tests to `Tests/CosmoOSTests/RichDocumentTests.swift`:

```swift
func testElementSerializerSeparatesElementNameFromInstanceTitle() {
    let definition = DocumentElementDefinition(
        id: UUID(uuidString: "AAAAAAA1-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        title: "Concept",
        systemIcon: "person.2.fill"
    )
    let instance = RichElementInstance(
        definitionID: definition.id,
        titleSnapshot: "Concept",
        systemIconSnapshot: "person.2.fill",
        isCollapsed: false,
        instanceTitleSnapshot: "Audience Situation"
    )
    let document = RichDocument(blocks: [
        RichBlock.element(instance, children: [.paragraph("Nested context")])
    ])

    let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 17, darkMode: false)
    let decorations = DocumentElementEditorDecoration.decorations(in: attributed)
    let roundTripped = RichDocumentSerializer.document(from: attributed)

    XCTAssertEqual(attributed.string.components(separatedBy: .newlines).first, "Audience Situation")
    XCTAssertEqual(decorations.first?.title, "Concept")
    XCTAssertEqual(decorations.first?.instanceTitle, "Audience Situation")
    XCTAssertEqual(roundTripped.blocks.first?.element?.titleSnapshot, "Concept")
    XCTAssertEqual(roundTripped.blocks.first?.element?.instanceTitleSnapshot, "Audience Situation")
}

func testTogglingCollapsedHidesChildrenButPreservesContext() {
    let definition = DocumentElementDefinition(
        id: UUID(uuidString: "BBBBBBB2-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        title: "Concept",
        systemIcon: "person.2.fill"
    )
    let element = RichBlock.element(definition, children: [
        .paragraph("This must remain stored")
    ])
    let document = RichDocument(blocks: [element])
    let id = try! XCTUnwrap(document.blocks.first?.element?.id)

    let collapsed = DocumentElementMutation.toggledCollapse(instanceID: id, in: document)

    XCTAssertEqual(collapsed.blocks.first?.element?.isCollapsed, true)
    XCTAssertEqual(collapsed.blocks.first?.children.first?.inlines.first?.text, "This must remain stored")

    let visible = RichDocumentSerializer.attributedString(from: collapsed, fontSize: 17, darkMode: false)
    XCTAssertFalse(visible.string.contains("This must remain stored"))

    let restored = RichDocumentSerializer.document(from: visible)
    XCTAssertEqual(restored.blocks.first?.children.first?.inlines.first?.text, "This must remain stored")
}
```

- [ ] **Step 2: Add layout tests**

Create `Tests/CosmoOSTests/DocumentElementHeaderLayoutTests.swift`:

```swift
import XCTest
@testable import CosmoOS

final class DocumentElementHeaderLayoutTests: XCTestCase {
    func testHeaderLayoutUsesLargeChevronHitTargetAndAspectFitIconRect() {
        let layout = DocumentElementHeaderLayout(
            chromeRect: CGRect(x: 20, y: 40, width: 720, height: 46),
            headerMidY: 63,
            elementName: "Concept",
            instanceTitle: "Audience Situation",
            depth: 0,
            fontSize: 17
        )

        XCTAssertEqual(layout.chevronHitRect.width, 28)
        XCTAssertEqual(layout.chevronHitRect.height, 28)
        XCTAssertTrue(layout.chevronHitRect.contains(CGPoint(x: 34, y: 63)))
        XCTAssertEqual(layout.iconRect.width, layout.iconRect.height)
        XCTAssertLessThanOrEqual(layout.iconRect.width, 15)
        XCTAssertLessThan(layout.nameRect.minX, layout.titleRect.minX)
    }

    func testHeaderLayoutScalesForNestedElements() {
        let layout = DocumentElementHeaderLayout(
            chromeRect: CGRect(x: 20, y: 40, width: 720, height: 46),
            headerMidY: 63,
            elementName: "Concept",
            instanceTitle: "Nested title",
            depth: 2,
            fontSize: 17
        )

        XCTAssertGreaterThan(layout.chevronHitRect.minX, 20)
        XCTAssertGreaterThan(layout.nameRect.minX, layout.iconRect.maxX)
    }
}
```

- [ ] **Step 3: Run tests and confirm they fail**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -derivedDataPath /tmp/cosmo-elements-derived -only-testing:CosmoOSTests/RichDocumentTests/testElementSerializerSeparatesElementNameFromInstanceTitle -only-testing:CosmoOSTests/RichDocumentTests/testTogglingCollapsedHidesChildrenButPreservesContext -only-testing:CosmoOSTests/DocumentElementHeaderLayoutTests test -quiet
```

Expected: fail with missing `instanceTitleSnapshot`, `DocumentElementMutation`, and `DocumentElementHeaderLayout`.

---

## Task 2: Fix The Data Model Without Losing Existing Documents

**Files:**
- Modify: `Editor/DocumentElements.swift`
- Modify: `Editor/RichDocument.swift`

- [ ] **Step 1: Add `instanceTitleSnapshot` with backward-compatible decoding**

Update `RichElementInstance` in `Editor/DocumentElements.swift`:

```swift
struct RichElementInstance: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var definitionID: UUID
    var titleSnapshot: String
    var systemIconSnapshot: String
    var isCollapsed: Bool
    var instanceTitleSnapshot: String

    init(
        id: UUID = UUID(),
        definitionID: UUID,
        titleSnapshot: String,
        systemIconSnapshot: String,
        isCollapsed: Bool = false,
        instanceTitleSnapshot: String = "Untitled"
    ) {
        self.id = id
        self.definitionID = definitionID
        self.titleSnapshot = titleSnapshot
        self.systemIconSnapshot = systemIconSnapshot
        self.isCollapsed = isCollapsed
        self.instanceTitleSnapshot = instanceTitleSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : instanceTitleSnapshot
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case definitionID
        case titleSnapshot
        case systemIconSnapshot
        case isCollapsed
        case instanceTitleSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        definitionID = try container.decode(UUID.self, forKey: .definitionID)
        titleSnapshot = try container.decodeIfPresent(String.self, forKey: .titleSnapshot) ?? "Element"
        systemIconSnapshot = try container.decodeIfPresent(String.self, forKey: .systemIconSnapshot) ?? "square.grid.2x2"
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        instanceTitleSnapshot = try container.decodeIfPresent(String.self, forKey: .instanceTitleSnapshot) ?? titleSnapshot
    }
}
```

- [ ] **Step 2: Update `RichBlock.element(_:)` to create a block title**

In `Editor/RichDocument.swift`, update the definition-based factory:

```swift
static func element(
    _ definition: DocumentElementDefinition,
    children: [RichBlock] = [],
    isCollapsed: Bool = false,
    instanceTitle: String = "Untitled"
) -> RichBlock {
    RichBlock.element(
        RichElementInstance(
            definitionID: definition.id,
            titleSnapshot: definition.title,
            systemIconSnapshot: definition.systemIcon,
            isCollapsed: isCollapsed,
            instanceTitleSnapshot: instanceTitle
        ),
        children: children
    )
}
```

- [ ] **Step 3: Update serializer attributes**

In `Editor/RichDocument.swift`, add a new attribute key:

```swift
static let elementInstanceTitle = NSAttributedString.Key("CosmoElementInstanceTitle")
```

Update `elementHeaderAttributedString` so the visible string is the instance title and the muted label remains the Element name:

```swift
let elementName = block.element?.titleSnapshot ?? "Element"
let instanceTitle = block.element?.instanceTitleSnapshot ?? "Untitled"
...
attributes[RichDocumentAttributeKeys.elementTitle] = elementName
attributes[RichDocumentAttributeKeys.elementInstanceTitle] = instanceTitle
return NSAttributedString(string: instanceTitle, attributes: attributes)
```

- [ ] **Step 4: Update attributed parsing**

In `elementBlock(from:)`, parse the Element name from the attribute and the instance title from the line string:

```swift
let elementName = stringAttribute(RichDocumentAttributeKeys.elementTitle, in: line) ?? "Element"
let instanceTitle = line.string.trimmingCharacters(in: .whitespacesAndNewlines)
let instance = RichElementInstance(
    id: instanceID,
    definitionID: definitionID,
    titleSnapshot: elementName.isEmpty ? "Element" : elementName,
    systemIconSnapshot: icon.isEmpty ? "square.grid.2x2" : icon,
    isCollapsed: collapsed,
    instanceTitleSnapshot: instanceTitle.isEmpty ? "Untitled" : instanceTitle
)
```

- [ ] **Step 5: Run the semantic tests**

Run the command from Task 1 Step 3.

Expected: the model tests pass; layout tests still fail until Task 3.

---

## Task 3: Centralize Header Layout And Hit Targets

**Files:**
- Modify: `Editor/DocumentElements.swift`

- [ ] **Step 1: Add decoration fields**

Update `DocumentElementEditorDecoration`:

```swift
var title: String
var instanceTitle: String
var instanceID: UUID
```

Populate them from attributes:

```swift
let instanceID = uuidValue(attributedString.attribute(
    RichDocumentAttributeKeys.elementInstanceID,
    at: range.location,
    effectiveRange: nil
)) ?? UUID()
let instanceTitle = attributedString.attribute(
    RichDocumentAttributeKeys.elementInstanceTitle,
    at: range.location,
    effectiveRange: nil
) as? String ?? string.substring(with: range)
```

- [ ] **Step 2: Add `DocumentElementHeaderLayout`**

Add this to `Editor/DocumentElements.swift`:

```swift
struct DocumentElementHeaderLayout: Equatable {
    var chromeRect: CGRect
    var headerMidY: CGFloat
    var elementName: String
    var instanceTitle: String
    var depth: Int
    var fontSize: CGFloat

    private var depthOffset: CGFloat { CGFloat(depth * 18) }
    private var originX: CGFloat { chromeRect.minX + 14 + depthOffset }

    var chevronHitRect: CGRect {
        CGRect(x: originX - 7, y: headerMidY - 14, width: 28, height: 28)
    }

    var chevronGlyphRect: CGRect {
        CGRect(x: originX + 2, y: headerMidY - 5, width: 10, height: 10)
    }

    var iconRect: CGRect {
        CGRect(x: chevronHitRect.maxX + 6, y: headerMidY - 7.5, width: 15, height: 15)
    }

    var nameRect: CGRect {
        let width = min(max(48, elementNameWidth), 148)
        return CGRect(x: iconRect.maxX + 12, y: headerMidY - 10, width: width, height: 20)
    }

    var titleRect: CGRect {
        CGRect(
            x: nameRect.maxX + 26,
            y: headerMidY - 10,
            width: max(80, chromeRect.maxX - nameRect.maxX - 42),
            height: 20
        )
    }

    private var elementNameWidth: CGFloat {
        NSString(string: elementName).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: max(13, fontSize - 3), weight: .medium)
        ]).width
    }
}
```

- [ ] **Step 3: Add pure collapse mutation**

Add this to `Editor/DocumentElements.swift`:

```swift
enum DocumentElementMutation {
    static func toggledCollapse(instanceID: UUID, in document: RichDocument) -> RichDocument {
        RichDocument(blocks: toggle(in: document.blocks, instanceID: instanceID))
    }

    private static func toggle(in blocks: [RichBlock], instanceID: UUID) -> [RichBlock] {
        blocks.map { block in
            var updated = block
            if updated.element?.id == instanceID {
                updated.element?.isCollapsed.toggle()
                return updated
            }
            updated.children = toggle(in: updated.children, instanceID: instanceID)
            return updated
        }
    }
}
```

- [ ] **Step 4: Run layout and mutation tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -derivedDataPath /tmp/cosmo-elements-derived -only-testing:CosmoOSTests/DocumentElementHeaderLayoutTests -only-testing:CosmoOSTests/RichDocumentTests/testTogglingCollapsedHidesChildrenButPreservesContext test -quiet
```

Expected: PASS.

---

## Task 4: Make The Header Interactive In TextKit

**Files:**
- Modify: `Editor/TextKitCoordinator.swift`

- [ ] **Step 1: Add a narrow callback to `CosmoTextView`**

Add:

```swift
var onToggleElementCollapse: ((UUID) -> Void)?
```

- [ ] **Step 2: Route chevron clicks before normal text clicks**

At the top of `mouseDown(with:)`, after the editable guard, add:

```swift
let localPoint = convert(event.locationInWindow, from: nil)
if let hit = elementHitTest(at: localPoint), hit.area == .collapseToggle {
    onToggleElementCollapse?(hit.instanceID)
    return
}
```

Add hit types and helper methods:

```swift
private enum ElementHitArea {
    case collapseToggle
    case header
}

private struct ElementHit {
    var instanceID: UUID
    var area: ElementHitArea
}

private func elementHitTest(at point: CGPoint) -> ElementHit? {
    guard let storage = textStorage,
          let layoutManager,
          let textContainer else { return nil }

    layoutManager.ensureLayout(for: textContainer)
    for decoration in DocumentElementEditorDecoration.decorations(in: storage) {
        guard let layout = headerLayout(for: decoration, layoutManager: layoutManager, textContainer: textContainer, storageLength: storage.length) else {
            continue
        }
        if layout.chevronHitRect.contains(point) {
            return ElementHit(instanceID: decoration.instanceID, area: .collapseToggle)
        }
    }
    return nil
}
```

- [ ] **Step 3: Use a shared `headerLayout(for:)` helper for draw and hit test**

Move the layout math currently inside `drawElementBlockDecorations` into:

```swift
private func headerLayout(
    for decoration: DocumentElementEditorDecoration,
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer,
    storageLength: Int
) -> DocumentElementHeaderLayout? {
    let headerGlyphRange = layoutManager.glyphRange(
        forCharacterRange: NSIntersectionRange(decoration.range, NSRange(location: 0, length: storageLength)),
        actualCharacterRange: nil
    )
    let headerGlyphRect = layoutManager.boundingRect(forGlyphRange: headerGlyphRange, in: textContainer)
    let blockGlyphRange = layoutManager.glyphRange(
        forCharacterRange: NSIntersectionRange(decoration.blockRange, NSRange(location: 0, length: storageLength)),
        actualCharacterRange: nil
    )
    let blockGlyphRect = layoutManager.boundingRect(forGlyphRange: blockGlyphRange, in: textContainer)
    guard headerGlyphRect.height > 0, blockGlyphRect.height > 0 else { return nil }

    let depthOffset = CGFloat(decoration.depth * 18)
    let chromeRect = CGRect(
        x: textContainerOrigin.x + depthOffset,
        y: textContainerOrigin.y + min(headerGlyphRect.minY, blockGlyphRect.minY) - 8,
        width: max(80, bounds.width - (textContainerOrigin.x * 2) - depthOffset),
        height: max(blockGlyphRect.maxY - blockGlyphRect.minY + 16, elementBlockBaseFontSize + 28)
    )

    return DocumentElementHeaderLayout(
        chromeRect: chromeRect,
        headerMidY: textContainerOrigin.y + headerGlyphRect.midY,
        elementName: decoration.title,
        instanceTitle: decoration.instanceTitle,
        depth: decoration.depth,
        fontSize: elementBlockBaseFontSize
    )
}
```

- [ ] **Step 4: Wire toggle mutation in the coordinator**

In `configureTextView`, set:

```swift
textView.onToggleElementCollapse = { [weak coordinator = context.coordinator] instanceID in
    guard let coordinator, let textView = coordinator.textViewReference else { return }
    coordinator.toggleElementCollapse(instanceID: instanceID, in: textView)
}
```

Add:

```swift
func toggleElementCollapse(instanceID: UUID, in textView: NSTextView) {
    let currentDocument = RichDocumentSerializer.document(from: textView.attributedString())
    let updatedDocument = DocumentElementMutation.toggledCollapse(instanceID: instanceID, in: currentDocument)
    let updatedAttributed = RichDocumentSerializer.attributedString(
        from: updatedDocument,
        fontSize: parent.fontSize,
        darkMode: parent.darkMode,
        singleLine: parent.singleLine,
        baseFontWeight: parent.baseFontWeight,
        titleMode: parent.titleConfiguration != nil
    )
    textView.textStorage?.setAttributedString(updatedAttributed)
    textView.setSelectedRange(NSRange(location: min(textView.selectedRange().location, updatedAttributed.length), length: 0))
    syncBindings(from: textView)
    notifyContentHeightChange(for: textView)
}
```

- [ ] **Step 5: Run build and related tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -derivedDataPath /tmp/cosmo-elements-derived -only-testing:CosmoOSTests/RichDocumentTests -only-testing:CosmoOSTests/DocumentElementHeaderLayoutTests test -quiet
```

Expected: PASS.

---

## Task 5: Redraw The Header To Match The Reference

**Files:**
- Modify: `Editor/TextKitCoordinator.swift`
- Modify: `Editor/RichDocument.swift`

- [ ] **Step 1: Make actual text quiet and aligned**

Update `elementHeaderAttributedString` in `Editor/RichDocument.swift`:

```swift
paragraphStyle.minimumLineHeight = 44
paragraphStyle.maximumLineHeight = 44
paragraphStyle.paragraphSpacing = 12
paragraphStyle.paragraphSpacingBefore = 8
paragraphStyle.firstLineHeadIndent = CGFloat(depth * 18) + 256
paragraphStyle.headIndent = CGFloat(depth * 18) + 256

attributes[.font] = NSFont.systemFont(ofSize: max(13, fontSize - 2), weight: .medium)
attributes[.foregroundColor] = darkMode
    ? NSColor.white.withAlphaComponent(0.72)
    : NSColor(DS.documentText).withAlphaComponent(0.74)
```

- [ ] **Step 2: Replace the hardcoded `"Element"` label**

In `drawElementTypeLabel`, pass `decoration.title` instead of a literal string:

```swift
private func drawElementName(_ name: String, in rect: CGRect, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: max(13, elementBlockBaseFontSize - 3), weight: .medium),
        .foregroundColor: color
    ]
    NSString(string: name).draw(in: rect, withAttributes: attributes)
}
```

- [ ] **Step 3: Use reference-grade colors**

Use:

```swift
private var elementBlockFillColor: NSColor {
    effectiveElementBlockDarkMode
        ? NSColor(red: 0.118, green: 0.122, blue: 0.127, alpha: 1.0)
        : NSColor.white
}

private var elementBlockStrokeColor: NSColor {
    effectiveElementBlockDarkMode
        ? NSColor.white.withAlphaComponent(0.10)
        : NSColor.black.withAlphaComponent(0.105)
}

private var elementLabelColor: NSColor {
    effectiveElementBlockDarkMode
        ? NSColor.white.withAlphaComponent(0.50)
        : NSColor(DS.documentTextSecondary).withAlphaComponent(0.78)
}
```

- [ ] **Step 4: Draw chevron manually in the correct orientation**

Use `drawElementChevron(collapsed:in:color:)` only. Do not use SF Symbol chevrons for this header.

Collapsed must point right. Expanded must point down.

- [ ] **Step 5: Ensure text does not overlap the drawn label**

After dynamic label width is used in `DocumentElementHeaderLayout`, update `firstLineHeadIndent` to a conservative value that covers the largest allowed label:

```swift
paragraphStyle.firstLineHeadIndent = CGFloat(depth * 18) + 260
paragraphStyle.headIndent = CGFloat(depth * 18) + 260
```

This is intentionally conservative because TextKit paragraph indents cannot depend on the per-instance label width.

---

## Task 6: Fix Icon Validation And Rendering

**Files:**
- Modify: `Editor/DocumentElements.swift`
- Modify: `Editor/TextKitCoordinator.swift`
- Modify: `Editor/SlashCommandMenu.swift`
- Modify: `Settings/SanctuarySettingsView.swift`

- [ ] **Step 1: Add symbol validation**

Add to `Editor/DocumentElements.swift`:

```swift
enum DocumentElementSymbol {
    static let fallback = "square.grid.2x2"

    static func validName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil else {
            return fallback
        }
        return trimmed
    }
}
```

Import AppKit in this file:

```swift
import AppKit
```

- [ ] **Step 2: Normalize icons at creation and update**

In `DocumentElementStore.normalizedIcon(_:)`, return:

```swift
DocumentElementSymbol.validName(systemIcon)
```

- [ ] **Step 3: Draw symbols aspect-fit**

Replace symbol drawing with:

```swift
private func drawElementBlockSymbol(name: String, in rect: CGRect, color: NSColor) {
    let validName = DocumentElementSymbol.validName(name)
    guard let image = NSImage(systemSymbolName: validName, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: min(rect.width, rect.height), weight: .medium)) else {
        return
    }
    image.isTemplate = true
    color.set()
    let side = min(rect.width, rect.height)
    let fitted = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
    image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}
```

- [ ] **Step 4: Remove raw invalid icon entry points**

In `ElementCreationMenu`, keep the icon picker. If a text field for raw symbols remains, validate on every submit with `DocumentElementSymbol.validName`.

- [ ] **Step 5: Add tests for fallback**

Add to `DocumentElementStoreTests`:

```swift
func testCreateDefinitionFallsBackForInvalidSymbol() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = DocumentElementStore(fileURL: directory.appendingPathComponent("Elements.json"))

    let definition = try store.createDefinition(title: "Concept", systemIcon: "not.a.symbol")

    XCTAssertEqual(definition.systemIcon, DocumentElementSymbol.fallback)
}
```

---

## Task 7: Keep SwiftUI Renderer In Sync

**Files:**
- Modify: `Editor/CosmoDocumentRenderer.swift`

- [ ] **Step 1: Update read-only rendering hierarchy**

Change the Element row to:

```swift
HStack(spacing: 12) {
    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(secondaryTextColor.opacity(0.82))
        .frame(width: 14)

    Image(systemName: DocumentElementSymbol.validName(DocumentElementRendering.systemIcon(for: block)))
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(secondaryTextColor.opacity(0.82))
        .frame(width: 16)

    Text(DocumentElementRendering.title(for: block))
        .font(.system(size: max(13, fontSize - 3), weight: .medium))
        .foregroundStyle(secondaryTextColor)
        .lineLimit(1)

    Text(block.element?.instanceTitleSnapshot ?? "Untitled")
        .font(.system(size: max(13, fontSize - 2), weight: .medium))
        .foregroundStyle(textColor.opacity(0.74))
        .lineLimit(1)

    Spacer(minLength: 0)
}
```

- [ ] **Step 2: Match fill and outline**

Use:

```swift
private func elementBackgroundColor(depth: Int) -> Color {
    darkMode ? Color(red: 0.118, green: 0.122, blue: 0.127) : .white
}

private var elementBorderColor: Color {
    darkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.105)
}
```

---

## Task 8: Manual Visual Verification

**Files:**
- No source changes unless visual issues are found.

- [ ] **Step 1: Build the app**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -derivedDataPath /tmp/cosmo-elements-derived build -quiet
```

Expected: build succeeds. Existing unrelated warnings may appear.

- [ ] **Step 2: Verify light mode by hand**

Open a note and create an Element named `Concept` with icon `person.2.fill`. Confirm:

- The left muted label says `Concept`, not `Element`.
- The icon renders as people, not a box.
- The icon is not stretched.
- The right title is smaller and quieter than body/title text.
- Chevron points right when collapsed and down when expanded.
- Clicking the chevron toggles collapse.
- Nested children hide visually when collapsed.

- [ ] **Step 3: Verify dark mode by hand**

Switch to a dark theme or dark editor surface. Confirm:

- Fill is dark, not white.
- Border is a thin low-contrast outline.
- Label/icon/chevron are muted gray.
- Title remains readable but not heavy.

- [ ] **Step 4: Run the full related regression suite**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -derivedDataPath /tmp/cosmo-elements-derived -only-testing:CosmoOSTests/DocumentElementStoreTests -only-testing:CosmoOSTests/RichDocumentTests -only-testing:CosmoOSTests/CosmoWindowMessageRenderingTests/testMentionExpansionPreservesElementStructureFromRichDocument -only-testing:CosmoOSTests/CosmoWindowContextSessionTests/testIndexableBodyPreservesElementStructureFromRichDocument test -quiet
```

Expected: PASS.

- [ ] **Step 5: Run hygiene checks**

Run:

```bash
rg -n "[[:blank:]]$" Editor/DocumentElements.swift Editor/RichDocument.swift Editor/TextKitCoordinator.swift Editor/CosmoDocumentRenderer.swift Editor/SlashCommandMenu.swift Settings/SanctuarySettingsView.swift Tests/CosmoOSTests/RichDocumentTests.swift Tests/CosmoOSTests/DocumentElementHeaderLayoutTests.swift
git diff --check -- Editor/RichDocument.swift Editor/TextKitCoordinator.swift Editor/CosmoDocumentRenderer.swift Editor/SlashCommandMenu.swift Settings/SanctuarySettingsView.swift Tests/CosmoOSTests/RichDocumentTests.swift
```

Expected: no output from either command.

---

## Self-Review

- Spec coverage: covers clickability, chevron orientation, icon fallback/rendering, hardcoded `Element` label, muted title typography, light/dark outline styling, collapsed child persistence, and AI context preservation through existing context tests.
- Placeholder scan: no TBD/TODO/fill-later steps.
- Type consistency: `instanceTitleSnapshot`, `DocumentElementHeaderLayout`, `DocumentElementMutation`, and `DocumentElementSymbol` are introduced before later tasks reference them.
