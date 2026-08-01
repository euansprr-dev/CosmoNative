import XCTest
@testable import CosmoOS

final class RichDocumentTests: XCTestCase {

    // MARK: - Numbered list seed (jury round 1)

    /// A block row serializes a single-block document; the seed carries the
    /// count of numbered siblings above so "2." can exist. Guard-twin note:
    /// renderedPrefixLength measures digits by regex, so multi-digit
    /// positions stay boundary-safe.
    func testNumberedListSeedRendersTruePosition() {
        let doc = RichDocument(blocks: [RichBlock(kind: .numberedList, inlines: [.text("beta")])])
        let seeded = RichDocumentSerializer.attributedString(from: doc, numberedListSeed: 1)
        XCTAssertTrue(seeded.string.hasPrefix("2. "), "seed 1 should render position 2, got: \(seeded.string.prefix(6))")

        let unseeded = RichDocumentSerializer.attributedString(from: doc)
        XCTAssertTrue(unseeded.string.hasPrefix("1. "))

        let multiDigit = RichDocumentSerializer.attributedString(from: doc, numberedListSeed: 11)
        XCTAssertTrue(multiDigit.string.hasPrefix("12. "))
        XCTAssertEqual(RichBlockKind.numberedList.renderedPrefixLength(in: multiDigit.string), 4)
    }

    /// Interior blocks of a multi-block document only inherit the seed when
    /// their run is unbroken from the document's first block.
    func testNumberedListSeedOnlyReachesRunsTouchingDocumentStart() {
        let doc = RichDocument(blocks: [
            RichBlock(kind: .numberedList, inlines: [.text("one")]),
            .paragraph("break"),
            RichBlock(kind: .numberedList, inlines: [.text("restart")])
        ])
        let seeded = RichDocumentSerializer.attributedString(from: doc, numberedListSeed: 4)
        XCTAssertTrue(seeded.string.hasPrefix("5. "), "first run continues the seed")
        XCTAssertTrue(seeded.string.contains("\n1. restart"), "a run after a break restarts at 1")
    }

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

    // The canvas thought card renders a note as flattened plain text, so it
    // must be refused for any document whose blocks carry visuals — the
    // serializer would show "[Sketch]" / "[Image]" and flattened elements.
    func testContainsVisualBlocksDetectsSketchImageAndElementAtAnyDepth() {
        XCTAssertFalse(RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Just words")]),
            RichBlock(kind: .checklist, inlines: [.text("and a task")], checked: false),
            RichBlock(kind: .toggle, inlines: [.text("folded")], children: [
                RichBlock(kind: .paragraph, inlines: [.text("text child")])
            ])
        ]).containsVisualBlocks)

        XCTAssertTrue(RichDocument(blocks: [
            RichBlock(kind: .sketch)
        ]).containsVisualBlocks)

        XCTAssertTrue(RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [
                .image(RichImageReference(path: "img.png", width: 100, height: 100, displayWidth: nil))
            ])
        ]).containsVisualBlocks)

        // Nested: a sketch inside a toggle's children.
        XCTAssertTrue(RichDocument(blocks: [
            RichBlock(kind: .toggle, inlines: [.text("folded")], children: [
                RichBlock(kind: .sketch)
            ])
        ]).containsVisualBlocks)

        // Hidden: an element folded away under a collapsed heading.
        XCTAssertTrue(RichDocument(blocks: [
            RichBlock(
                kind: .heading2,
                inlines: [.text("Section")],
                heading: RichHeadingMetadata(
                    isCollapsed: true,
                    collapsedBlocks: [
                        RichBlock(
                            kind: .element,
                            element: RichElementInstance(
                                definitionID: UUID(),
                                titleSnapshot: "Audience Situation",
                                systemIconSnapshot: "person.2",
                                isCollapsed: false,
                                instanceTitleSnapshot: "Audience Situation",
                                tintSnapshot: "sage"
                            )
                        )
                    ],
                    isCollapsible: true
                )
            )
        ]).containsVisualBlocks)
    }

    func testContentAndResearchBlocksContributePlainText() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .content, inlines: [.text("Draft the story")]),
            RichBlock(kind: .research, inlines: [.text("Find source material")])
        ])

        XCTAssertEqual(document.plainText, "Draft the story\nFind source material")
    }

    @MainActor
    func testBlockFocusCoordinatorMovesWithinRegisteredBlocks() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let third = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let coordinator = BlockFocusCoordinator()

        coordinator.register(first)
        coordinator.register(second)
        coordinator.register(third)
        coordinator.focus(second)

        coordinator.focusNext()
        XCTAssertEqual(coordinator.focusedBlockID, third)
        XCTAssertFalse(coordinator.focusNext())
        XCTAssertEqual(coordinator.focusedBlockID, third)

        coordinator.focusPrevious()
        XCTAssertEqual(coordinator.focusedBlockID, second)
    }

    @MainActor
    func testBlockFocusCoordinatorNavigatesInDocumentOrderNotRegistrationOrder() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let third = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let coordinator = BlockFocusCoordinator()

        // Rows can mount in any order (AppKit onAppear timing). Register them
        // reversed to prove navigation ignores registration order.
        coordinator.register(third)
        coordinator.register(second)
        coordinator.register(first)
        coordinator.syncNavigationOrder([first, second, third])

        coordinator.focus(second)
        // ⬇ moves to the block visually below (third), not the next registered.
        XCTAssertTrue(coordinator.focusNext())
        XCTAssertEqual(coordinator.focusedBlockID, third)
        // ⬆ moves back up in document order.
        XCTAssertTrue(coordinator.focusPrevious())
        XCTAssertEqual(coordinator.focusedBlockID, second)
        XCTAssertTrue(coordinator.focusPrevious())
        XCTAssertEqual(coordinator.focusedBlockID, first)
        // Already at the top — no wrap.
        XCTAssertFalse(coordinator.focusPrevious())
        XCTAssertEqual(coordinator.focusedBlockID, first)
    }

    // MARK: - Per-row focus states (invalidation granularity)

    @MainActor
    func testFocusChangeFlipsOnlyTheTwoAffectedRowStates() {
        let first = UUID(), second = UUID(), third = UUID()
        let coordinator = BlockFocusCoordinator()
        coordinator.register(first)
        coordinator.register(second)
        coordinator.register(third)

        coordinator.focus(first)
        XCTAssertTrue(coordinator.rowState(for: first).isFocused)
        XCTAssertFalse(coordinator.rowState(for: second).isFocused)

        coordinator.focus(second)
        XCTAssertFalse(coordinator.rowState(for: first).isFocused)
        XCTAssertTrue(coordinator.rowState(for: second).isFocused)
        XCTAssertFalse(coordinator.rowState(for: third).isFocused)
        XCTAssertEqual(coordinator.focusedBlockID, second)
        XCTAssertTrue(coordinator.hasFocusedBlock)
    }

    @MainActor
    func testCaretRequestLandsOnlyOnTheTargetRowState() {
        let first = UUID(), second = UUID()
        let coordinator = BlockFocusCoordinator()
        coordinator.register(first)
        coordinator.register(second)

        coordinator.focus(second, caretOffsetFromEnd: 3)
        XCTAssertNil(coordinator.rowState(for: first).caretRequest)
        XCTAssertEqual(coordinator.rowState(for: second).caretRequest?.utf16OffsetFromEnd, 3)
        XCTAssertEqual(coordinator.rowState(for: second).caretRequest?.blockID, second)
    }

    @MainActor
    func testCommandTargetFollowsFocusThenFallsBackToFirstRegistered() {
        let first = UUID(), second = UUID()
        let coordinator = BlockFocusCoordinator()
        coordinator.register(first)
        coordinator.register(second)

        // Nothing focused: the first registered row routes commands.
        XCTAssertTrue(coordinator.rowState(for: first).isCommandTarget)
        XCTAssertFalse(coordinator.rowState(for: second).isCommandTarget)
        XCTAssertEqual(coordinator.commandTargetID(for: first, baseTargetID: "note"), "note")
        XCTAssertEqual(
            coordinator.commandTargetID(for: second, baseTargetID: "note"),
            "note:block:\(second.uuidString)"
        )

        coordinator.focus(second)
        XCTAssertFalse(coordinator.rowState(for: first).isCommandTarget)
        XCTAssertTrue(coordinator.rowState(for: second).isCommandTarget)

        // Unregistering the focused row hands routing back to the first.
        coordinator.unregister(second)
        XCTAssertTrue(coordinator.rowState(for: first).isCommandTarget)
        XCTAssertFalse(coordinator.hasFocusedBlock)
    }

    // MARK: - Self-authored ledger (typing echo skip)

    @MainActor
    func testSelfAuthoredEchoSkipsOnlyExactOwnWrites() {
        let coordinator = BlockFocusCoordinator()
        var block = RichBlock(kind: .paragraph, inlines: [.text("hell")])
        let previous = block
        block.inlines = [.text("hello")]

        // Not in the ledger yet — an unknown change is external, re-render.
        XCTAssertFalse(coordinator.isSelfAuthoredEcho(previous: previous, next: block))

        // The row wrote it — the echo is safe to skip.
        coordinator.noteSelfAuthoredBlock(block)
        XCTAssertTrue(coordinator.isSelfAuthoredEcho(previous: previous, next: block))

        // An external write differing from the ledger must re-render.
        var external = block
        external.inlines = [.text("hello there")]
        XCTAssertFalse(coordinator.isSelfAuthoredEcho(previous: previous, next: external))
    }

    @MainActor
    func testSelfAuthoredEchoNeverSkipsKindHeadingEmptinessOrChildrenChanges() {
        let coordinator = BlockFocusCoordinator()
        let id = UUID()

        // Kind change (paragraph → heading) must re-render even if ledgered.
        var previous = RichBlock(kind: .paragraph, inlines: [.text("title")])
        previous.id = id
        var next = previous
        next.kind = .heading1
        coordinator.noteSelfAuthoredBlock(next)
        XCTAssertFalse(coordinator.isSelfAuthoredEcho(previous: previous, next: next))

        // Emptiness flip (placeholder visibility) must re-render.
        var emptyPrevious = RichBlock(kind: .paragraph, inlines: [.text("")])
        emptyPrevious.id = id
        var nonEmptyNext = emptyPrevious
        nonEmptyNext.inlines = [.text("a")]
        coordinator.noteSelfAuthoredBlock(nonEmptyNext)
        XCTAssertFalse(coordinator.isSelfAuthoredEcho(previous: emptyPrevious, next: nonEmptyNext))

        // Children (toggle bodies) render from the row snapshot — never skip.
        var childPrevious = RichBlock(kind: .toggle, inlines: [.text("t")])
        childPrevious.id = id
        var childNext = childPrevious
        childNext.children = [RichBlock(kind: .paragraph, inlines: [.text("child")])]
        coordinator.noteSelfAuthoredBlock(childNext)
        XCTAssertFalse(coordinator.isSelfAuthoredEcho(previous: childPrevious, next: childNext))
    }

    @MainActor
    func testBlockFocusCoordinatorSkipsUnmountedBlocksInDocumentOrder() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let hiddenMiddle = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let third = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let coordinator = BlockFocusCoordinator()

        // The middle block exists in the document order but has no live editor
        // (e.g. a collapsed element child) — navigation should step over it.
        coordinator.register(first)
        coordinator.register(third)
        coordinator.syncNavigationOrder([first, hiddenMiddle, third])

        coordinator.focus(first)
        XCTAssertTrue(coordinator.focusNext())
        XCTAssertEqual(coordinator.focusedBlockID, third)
    }

    @MainActor
    func testBlockFocusCoordinatorDoesNotJumpToFirstBlockWhenFocusIsUnknown() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let coordinator = BlockFocusCoordinator()

        coordinator.register(first)
        coordinator.register(second)

        XCTAssertFalse(coordinator.focusNext())
        XCTAssertNil(coordinator.focusedBlockID)
        XCTAssertFalse(coordinator.focusPrevious())
        XCTAssertNil(coordinator.focusedBlockID)
    }

    @MainActor
    func testBlockFocusCoordinatorRoutesBaseCommandTargetToFocusedBlockOnly() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let coordinator = BlockFocusCoordinator()

        coordinator.register(first)
        coordinator.register(second)
        coordinator.focus(second)

        XCTAssertEqual(coordinator.commandTargetID(for: second, baseTargetID: "note-body"), "note-body")
        XCTAssertEqual(
            coordinator.commandTargetID(for: first, baseTargetID: "note-body"),
            "note-body:block:\(first.uuidString)"
        )
    }

    func testBlockSplitterGroupsTextRunsAroundElementBlocks() {
        let audience = DocumentElementDefinition(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Audience",
            systemIcon: "person.2"
        )
        let offer = DocumentElementDefinition(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Offer",
            systemIcon: "sparkles"
        )
        let blocks: [RichBlock] = [
            .paragraph("Intro"),
            RichBlock(kind: .heading2, inlines: [.text("Context")]),
            .element(audience),
            RichBlock(kind: .bulletList, inlines: [.text("One")]),
            RichBlock(kind: .checklist, inlines: [.text("Done")], checked: false),
            .element(offer)
        ]

        let regions = BlockSplitter.split(blocks)

        XCTAssertEqual(regions.map(\.range), [0..<2, 2..<3, 3..<5, 5..<6])
        XCTAssertEqual(regions.map(\.kind), [.text, .element, .text, .element])
        XCTAssertEqual(regions[0].blocks.map(\.kind), [.paragraph, .heading2])
        XCTAssertEqual(regions[2].blocks.map(\.kind), [.bulletList, .checklist])
    }

    func testTextRegionIdentitySurvivesParagraphSplits() {
        let anchorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let insertedID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let before = BlockSplitter.split([
            RichBlock(id: anchorID, kind: .paragraph, inlines: [.text("First")])
        ])
        let after = BlockSplitter.split([
            RichBlock(id: anchorID, kind: .paragraph, inlines: [.text("First")]),
            RichBlock(id: insertedID, kind: .paragraph, inlines: [.text("Second")])
        ])

        XCTAssertEqual(before.first?.id, after.first?.id)
    }

    func testTextRegionResolvedRangeFollowsCurrentTextRunAfterParagraphSplit() {
        let anchorID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let insertedID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let staleRegion = BlockRegion(
            kind: .text,
            range: 0..<1,
            blocks: [
                RichBlock(id: anchorID, kind: .paragraph, inlines: [.text("First")])
            ]
        )
        let currentBlocks = [
            RichBlock(id: anchorID, kind: .paragraph, inlines: [.text("First")]),
            RichBlock(id: insertedID, kind: .paragraph, inlines: [.text("Second")])
        ]

        XCTAssertEqual(
            BlockRegionReplacement.resolvedRange(for: staleRegion, in: currentBlocks),
            0..<2
        )
    }

    func testTextRegionResolvedRangeStopsAtElementBoundary() {
        let definition = DocumentElementDefinition(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            title: "Insight",
            systemIcon: "sparkles"
        )
        let staleRegion = BlockRegion(
            kind: .text,
            range: 0..<1,
            blocks: [.paragraph("First")]
        )
        let currentBlocks: [RichBlock] = [
            .paragraph("First"),
            .paragraph("Second"),
            .element(definition),
            .paragraph("Third")
        ]

        XCTAssertEqual(
            BlockRegionReplacement.resolvedRange(for: staleRegion, in: currentBlocks),
            0..<2
        )
    }

    func testBlockSplitterDoesNotGroupDividerImageOrElementIntoTextRegions() {
        let definition = DocumentElementDefinition(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "Insight",
            systemIcon: "sparkles"
        )
        let blocks: [RichBlock] = [
            .paragraph("Before"),
            RichBlock(kind: .divider),
            RichBlock(kind: .image, inlines: [
                .image(RichImageReference(path: "images/test.png", width: 320, height: 180))
            ]),
            .element(definition),
            .paragraph("After")
        ]

        let regions = BlockSplitter.split(blocks)

        XCTAssertEqual(regions.map(\.range), [0..<1, 1..<2, 2..<3, 3..<4, 4..<5])
        XCTAssertEqual(regions.map(\.kind), [.text, .unsupported, .unsupported, .element, .text])
    }

    func testBlockRegionReplacementSkipsFlushWhenExpandedBlocksAreAlreadyApplied() {
        let paragraph = RichBlock.paragraph("Intro")
        let element = RichBlock.element(
            DocumentElementDefinition(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                title: "Map",
                systemIcon: "map"
            ),
            instanceTitle: "Map"
        )
        let trailing = RichBlock.paragraph("")
        let blocks = [paragraph, element, trailing]

        let updated = BlockRegionReplacement.replacingBlocks(
            in: blocks,
            range: 0..<1,
            with: blocks
        )

        XCTAssertEqual(updated, blocks)
    }

    func testBlockRegionReplacementExpandsRegionWhenInsertionIsNotYetApplied() {
        let paragraph = RichBlock.paragraph("Intro")
        let element = RichBlock.element(
            DocumentElementDefinition(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                title: "Insight",
                systemIcon: "sparkles"
            ),
            instanceTitle: "Insight"
        )
        let trailing = RichBlock.paragraph("")

        let updated = BlockRegionReplacement.replacingBlocks(
            in: [paragraph],
            range: 0..<1,
            with: [paragraph, element, trailing]
        )

        XCTAssertEqual(updated, [paragraph, element, trailing])
    }

    func testAttributedSerializerPreservesTrailingEmptyLineAfterReturn() {
        let attributed = NSAttributedString(string: "Intro\n")

        let document = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks.first?.plainInlineText, "Intro")
        XCTAssertEqual(document.blocks.last?.kind, .paragraph)
        XCTAssertEqual(document.blocks.last?.plainInlineText, "")
    }

    func testElementInsertionSerializationKeepsEditableParagraphAfterElement() {
        let definition = DocumentElementDefinition(
            id: UUID(uuidString: "66666666-5555-4444-3333-222222222222")!,
            title: "Map",
            systemIcon: "map"
        )
        let element = RichBlock.element(definition, instanceTitle: "Map")
        let attributed = NSMutableAttributedString()
        attributed.append(RichDocumentSerializer.attributedString(from: RichDocument(blocks: [element])))
        attributed.append(NSAttributedString(string: "\n"))

        let document = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(document.blocks.map(\.kind), [.element, .paragraph])
        XCTAssertEqual(document.blocks.first?.element?.instanceTitleSnapshot, "Map")
        XCTAssertEqual(document.blocks.last?.plainInlineText, "")
    }

    func testTextRegionStructuralEditTrackerPreservesInsertedElementAfterEagerBindingUpdate() {
        let original = [RichBlock.paragraph("")]
        let definition = DocumentElementDefinition(
            id: UUID(uuidString: "77777777-5555-4444-3333-222222222222")!,
            title: "Audience",
            systemIcon: "person.2"
        )
        let inserted = RichBlock.element(definition, instanceTitle: "Audience")
        let replacement = [inserted, RichBlock.paragraph("")]

        var tracker = TextRegionStructuralEditTracker()
        tracker.recordUpdate(from: original, to: replacement)

        XCTAssertEqual(tracker.consumeInsertedElementID(), inserted.id)
        XCTAssertNil(tracker.consumeInsertedElementID())
    }

    func testCanvasPreviewUsesLazyDocumentStacksForLongNotes() {
        XCTAssertEqual(
            CosmoDocumentRendererStackPolicy.mode(
                for: .canvasPreview,
                blockCount: CosmoDocumentRendererStackPolicy.canvasPreviewLazyBlockThreshold
            ),
            .lazy
        )
    }

    func testFullDocumentSurfaceKeepsEagerStacksForLongNotes() {
        XCTAssertEqual(
            CosmoDocumentRendererStackPolicy.mode(
                for: .fullDocument,
                blockCount: CosmoDocumentRendererStackPolicy.canvasPreviewLazyBlockThreshold * 4
            ),
            .eager
        )
    }

    func testLegacyMigrationParsesRequestedSlashBlocks() {
        let document = RichDocument.migrateLegacy(
            """
            # Title
            ## Subtitle
            ### Section
            │ Quote
            • Bullet
            1. Numbered
            ☑ Done
            ☐ Todo
            ---
            """
        )

        XCTAssertEqual(
            document.blocks.map(\.kind),
            [.heading1, .heading2, .heading3, .quote, .bulletList, .numberedList, .checklist, .checklist, .divider]
        )
        XCTAssertEqual(document.blocks[6].checked, true)
        XCTAssertEqual(document.blocks[7].checked, false)
    }

    func testPlainTextIncludesMentionsAndImages() {
        let mention = RichMention(
            entityUUID: "note-uuid",
            entityID: 42,
            entityType: .note,
            titleSnapshot: "Michael"
        )
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [
                .text("Hello "),
                .mention(mention),
                .text("!")
            ]),
            RichBlock(kind: .image, inlines: [
                .image(RichImageReference(path: "images/test.png", width: 320, height: 180))
            ])
        ])

        XCTAssertEqual(document.plainText, "Hello @Michael!\n[Image]")
    }

    func testElementBlocksPersistNestedChildrenAndPlainText() throws {
        let audience = DocumentElementDefinition(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Target Audience",
            systemIcon: "person.2.fill"
        )
        let pains = DocumentElementDefinition(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Pain Points",
            systemIcon: "exclamationmark.bubble"
        )
        let document = RichDocument(blocks: [
            RichBlock.element(audience, children: [
                .paragraph("High-agency founders"),
                RichBlock.element(pains, children: [
                    .paragraph("They feel scattered")
                ], isCollapsed: true)
            ])
        ])

        let data = try JSONEncoder().encode(document)
        let roundTripped = try JSONDecoder().decode(RichDocument.self, from: data)

        XCTAssertEqual(roundTripped, document)
        XCTAssertEqual(roundTripped.blocks.first?.element?.titleSnapshot, "Target Audience")
        XCTAssertEqual(roundTripped.blocks.first?.children.last?.element?.isCollapsed, true)
        XCTAssertEqual(
            roundTripped.plainText,
            """
            Target Audience
              High-agency founders
              Pain Points
                They feel scattered
            """
        )
    }

    func testRichBlockDecodesLegacyJSONWithoutElementFields() throws {
        let json = """
        {
          "blocks": [
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "kind": "paragraph",
              "inlines": []
            }
          ]
        }
        """

        let document = try JSONDecoder().decode(RichDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.blocks.first?.kind, .paragraph)
        XCTAssertEqual(document.blocks.first?.children, [])
        XCTAssertNil(document.blocks.first?.element)
    }

    func testElementRenderingStateHidesCollapsedChildren() {
        let definition = DocumentElementDefinition(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "Offer Stack",
            systemIcon: "square.stack.3d.up"
        )
        let collapsed = RichBlock.element(definition, children: [
            .paragraph("Core offer")
        ], isCollapsed: true)
        let expanded = RichBlock.element(definition, children: [
            .paragraph("Core offer")
        ])

        XCTAssertEqual(DocumentElementRendering.visibleChildBlocks(for: collapsed), [])
        XCTAssertEqual(
            DocumentElementRendering.visibleChildBlocks(for: expanded)
                .map { RichDocument(blocks: [$0]).plainText },
            ["Core offer"]
        )
    }

    func testAttributedSerializerRoundTripsExpandedElementChildren() {
        let audience = DocumentElementDefinition(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "Target Audience",
            systemIcon: "person.2.fill"
        )
        let document = RichDocument(blocks: [
            RichBlock.element(audience, children: [
                .paragraph("High-agency founders"),
                RichBlock(kind: .checklist, inlines: [.text("Needs clarity")], checked: false)
            ])
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document)
        let roundTripped = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(roundTripped.blocks.count, 1)
        XCTAssertEqual(roundTripped.blocks.first?.kind, .element)
        XCTAssertEqual(roundTripped.blocks.first?.element?.definitionID, audience.id)
        XCTAssertEqual(roundTripped.blocks.first?.element?.titleSnapshot, "Target Audience")
        XCTAssertEqual(roundTripped.blocks.first?.element?.systemIconSnapshot, "person.2.fill")
        XCTAssertEqual(roundTripped.blocks.first?.children.map(\.kind), [.paragraph, .checklist])
        XCTAssertEqual(roundTripped.blocks.first?.children.first?.inlines.first?.text, "High-agency founders")
        XCTAssertEqual(roundTripped.blocks.first?.children.last?.checked, false)
    }

    func testAttributedSerializerPreservesCollapsedElementChildrenSnapshot() {
        let offer = DocumentElementDefinition(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            title: "Offer Stack",
            systemIcon: "square.stack.3d.up"
        )
        let document = RichDocument(blocks: [
            RichBlock.element(offer, children: [
                .paragraph("Core offer")
            ], isCollapsed: true)
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document)
        let roundTripped = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(roundTripped.blocks.count, 1)
        XCTAssertEqual(roundTripped.blocks.first?.element?.isCollapsed, true)
        XCTAssertEqual(roundTripped.blocks.first?.children.first?.inlines.first?.text, "Core offer")
    }

    func testElementEditorDecorationFindsSerializedElementHeader() {
        let audience = DocumentElementDefinition(
            title: "Target Audience",
            systemIcon: "person.2.fill"
        )
        let attributed = RichDocumentSerializer.attributedString(
            from: RichDocument(blocks: [
                RichBlock.paragraph("Intro"),
                RichBlock.element(audience),
                RichBlock.paragraph("Outro")
            ]),
            fontSize: 16,
            darkMode: false
        )

        let decorations = DocumentElementEditorDecoration.decorations(in: attributed)

        XCTAssertEqual(decorations.count, 1)
        XCTAssertEqual(decorations.first?.systemIcon, "person.2.fill")
        XCTAssertEqual(decorations.first?.title, "Target Audience")
        XCTAssertEqual(decorations.first?.isCollapsed, false)
    }

    func testElementEditorDecorationIncludesExpandedChildRange() {
        let audience = DocumentElementDefinition(
            title: "Target Audience",
            systemIcon: "person.2.fill"
        )
        let attributed = RichDocumentSerializer.attributedString(
            from: RichDocument(blocks: [
                RichBlock.element(audience, children: [
                    .paragraph("High-agency founders")
                ])
            ]),
            fontSize: 16,
            darkMode: false
        )

        let decoration = DocumentElementEditorDecoration.decorations(in: attributed).first

        XCTAssertNotNil(decoration)
        XCTAssertGreaterThan(decoration?.blockRange.length ?? 0, decoration?.range.length ?? 0)
        XCTAssertTrue((attributed.string as NSString).substring(with: decoration?.blockRange ?? NSRange()).contains("High-agency founders"))
    }

    func testElementSerializerSeparatesElementNameFromInstanceTitle() throws {
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

        XCTAssertEqual(attributed.string.components(separatedBy: CharacterSet.newlines).first, "Audience Situation")
        XCTAssertEqual(decorations.first?.title, "Concept")
        XCTAssertEqual(decorations.first?.instanceTitle, "Audience Situation")
        XCTAssertEqual(roundTripped.blocks.first?.element?.titleSnapshot, "Concept")
        XCTAssertEqual(roundTripped.blocks.first?.element?.instanceTitleSnapshot, "Audience Situation")
    }

    func testTogglingCollapsedHidesChildrenButPreservesContext() throws {
        let definition = DocumentElementDefinition(
            id: UUID(uuidString: "BBBBBBB2-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            title: "Concept",
            systemIcon: "person.2.fill"
        )
        let element = RichBlock.element(definition, children: [
            .paragraph("This must remain stored")
        ])
        let document = RichDocument(blocks: [element])
        let id = try XCTUnwrap(document.blocks.first?.element?.id)

        let collapsed = DocumentElementMutation.toggledCollapse(instanceID: id, in: document)

        XCTAssertEqual(collapsed.blocks.first?.element?.isCollapsed, true)
        XCTAssertEqual(collapsed.blocks.first?.children.first?.inlines.first?.text, "This must remain stored")

        let visible = RichDocumentSerializer.attributedString(from: collapsed, fontSize: 17, darkMode: false)
        XCTAssertFalse(visible.string.contains("This must remain stored"))

        let restored = RichDocumentSerializer.document(from: visible)
        XCTAssertEqual(restored.blocks.first?.children.first?.inlines.first?.text, "This must remain stored")
    }

    func testMetadataPersistenceRoundTripsTitleAndBodyDocuments() {
        let titleDocument = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Connected Note")])
        ])
        let bodyDocument = RichDocument(blocks: [
            RichBlock(kind: .checklist, inlines: [.text("Ship mentions")], checked: true),
            RichBlock(kind: .paragraph, inlines: [.text("Linked to @Michael")])
        ])

        let fields = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: nil,
            titleDocument: titleDocument,
            bodyDocument: bodyDocument
        )

        XCTAssertEqual(fields.title, "Connected Note")
        XCTAssertEqual(fields.body, bodyDocument.plainText)
        XCTAssertEqual(
            RichDocumentPersistence.loadAtomDocument(field: .title, metadata: fields.metadata, fallbackPlainText: nil),
            titleDocument
        )
        XCTAssertEqual(
            RichDocumentPersistence.loadAtomDocument(field: .body, metadata: fields.metadata, fallbackPlainText: nil),
            bodyDocument
        )
    }

    func testNoteFocusInitialDocumentsHydrateBodyFromAtomBeforeObservation() {
        let atom = Atom.new(
            type: .note,
            title: "Focus title",
            body: "Line one\nLine two"
        )

        let initialDocuments = NoteFocusInitialDocuments.from(atom: atom)

        XCTAssertEqual(initialDocuments.titlePlainText, "Focus title")
        XCTAssertEqual(initialDocuments.plainContent, "Line one\nLine two")
        XCTAssertEqual(initialDocuments.bodyDocument.plainText, "Line one\nLine two")
    }

    func testAttributedSerializerRoundTripsInlineMarksAndMentionMetadata() {
        let mention = RichMention(
            entityUUID: "connection-uuid",
            entityID: 7,
            entityType: .connection,
            titleSnapshot: "System"
        )
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [
                .text("Bold", marks: [.bold]),
                .text(" + "),
                .text("Italic", marks: [.italic]),
                .text(" + "),
                .text("Underline", marks: [.underline]),
                .text(" "),
                .mention(mention)
            ]),
            RichBlock(kind: .checklist, inlines: [.text("Complete")], checked: true)
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 16, darkMode: false)
        let roundTripped = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(roundTripped.plainText, document.plainText)
        XCTAssertEqual(roundTripped.blocks.first?.inlines.first?.marks, [.bold])
        XCTAssertEqual(roundTripped.blocks.first?.inlines[2].marks, [.italic])
        XCTAssertEqual(roundTripped.blocks.first?.inlines[4].marks, [.underline])
        XCTAssertEqual(roundTripped.blocks.first?.inlines.last?.mention, mention)
        XCTAssertEqual(roundTripped.blocks.last?.checked, true)
    }

    func testTitleNormalizationStripsHeadingFormatting() {
        let headingTitle = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [.text("Burger King", marks: [.bold])])
        ])

        let normalized = RichDocumentPersistence.normalizedTitleDocument(headingTitle)

        XCTAssertEqual(RichDocumentPersistence.titlePlainText(from: headingTitle), "Burger King")
        XCTAssertEqual(normalized.blocks.count, 1)
        XCTAssertEqual(normalized.blocks.first?.kind, .paragraph)
        XCTAssertEqual(normalized.plainText, "Burger King")
    }

    func testTitleNormalizationPreservesInlineMarksAndMentions() {
        let mention = RichMention(
            entityUUID: "connection-uuid",
            entityID: 7,
            entityType: .connection,
            titleSnapshot: "System"
        )
        let document = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [
                .text("  Alpha", marks: [.bold]),
                .text(" "),
                .mention(mention)
            ]),
            RichBlock(kind: .bulletList, inlines: [
                .text("Beta\nGamma", marks: [.italic])
            ]),
            RichBlock(kind: .image, inlines: [
                .image(RichImageReference(path: "images/title.png", width: 128, height: 96))
            ])
        ])

        let normalized = RichDocumentPersistence.normalizedTitleDocument(document)

        XCTAssertEqual(normalized.blocks.count, 1)
        XCTAssertEqual(normalized.blocks.first?.kind, .paragraph)
        XCTAssertEqual(RichDocumentPersistence.titlePlainText(from: normalized), "Alpha @System Beta Gamma")
        XCTAssertEqual(normalized.blocks.first?.inlines.first?.marks, [.bold])
        XCTAssertEqual(normalized.blocks.first?.inlines[2].mention, mention)
        XCTAssertEqual(normalized.blocks.first?.inlines.last?.marks, [.italic])
    }

    func testTitleNormalizationCollapsesWhitespaceAcrossBlocks() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("  First\nLine  ")]),
            RichBlock(kind: .checklist, inlines: [.text("Second\n\nLine")], checked: true),
            RichBlock(kind: .divider),
            RichBlock(kind: .quote, inlines: [.text(" Third ")])
        ])

        let normalized = RichDocumentPersistence.normalizedTitleDocument(document)

        XCTAssertEqual(normalized.blocks.count, 1)
        XCTAssertEqual(normalized.blocks.first?.kind, .paragraph)
        XCTAssertEqual(normalized.plainText, "First Line Second Line Third")
        XCTAssertEqual(RichDocumentPersistence.titlePlainText(from: normalized), "First Line Second Line Third")
    }

    func testTitlePayloadFactoryReturnsNormalizedDocumentAndMatchingPlainText() {
        let sourceDocument = RichDocument(blocks: [
            RichBlock(kind: .heading1, inlines: [
                .text("Burger", marks: [.bold])
            ]),
            RichBlock(kind: .paragraph, inlines: [
                .text(" King")
            ])
        ])
        let attributed = RichDocumentSerializer.attributedString(
            from: sourceDocument,
            fontSize: 32,
            darkMode: false,
            baseFontWeight: .bold
        )

        let payload = TitleDocumentChangePayloadFactory.payload(from: attributed)

        XCTAssertEqual(payload.plainText, "Burger King")
        XCTAssertEqual(payload.document.blocks.count, 1)
        XCTAssertEqual(payload.document.blocks.first?.kind, .paragraph)
        XCTAssertEqual(payload.document.plainText, "Burger King")
    }

    func testLoadAtomDocumentPrefersFallbackPlainTextWhenMetadataBodyIsShorter() {
        let truncatedBody = String(repeating: "A", count: 80)
        let fullBody = String(repeating: "B", count: 240)
        let fields = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: nil,
            bodyDocument: RichDocument.migrateLegacy(truncatedBody)
        )

        let loaded = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: fields.metadata,
            fallbackPlainText: fullBody,
            preferFallbackPlainTextWhenRicher: true
        )

        XCTAssertEqual(loaded.plainText, fullBody)
    }

    func testLoadAtomDocumentPrefersFallbackPlainTextWhenMetadataBodyDiffersAtSameLength() {
        let staleBody = "Alpha beta gamma"
        let currentBody = "Delta zeta theta"
        XCTAssertEqual(staleBody.count, currentBody.count)
        let fields = RichDocumentPersistence.writeAtomDocuments(
            existingMetadata: nil,
            bodyDocument: RichDocument.migrateLegacy(staleBody)
        )

        let loaded = RichDocumentPersistence.loadAtomDocument(
            field: .body,
            metadata: fields.metadata,
            fallbackPlainText: currentBody,
            preferFallbackPlainTextWhenRicher: true
        )

        XCTAssertEqual(loaded.plainText, currentBody)
    }

    func testNoteSnapshotPrefersPlainBodyWhenStructuredDocumentLags() {
        let staleBody = "Short body"
        let fullBody = Array(repeating: "This is the body that should win.", count: 8).joined(separator: " ")
        let snapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: nil,
            titleDocument: RichDocument.migrateLegacy("Recovered note"),
            bodyDocument: RichDocument.migrateLegacy(staleBody),
            plainBodyText: fullBody
        )

        XCTAssertEqual(snapshot.bodyPlainText, fullBody)
        XCTAssertEqual(snapshot.bodyDocument.plainText, fullBody)

        let payload = snapshot.noteFocusStatePayload(atomUUID: "note-uuid")
        XCTAssertEqual(payload["body"] as? String, fullBody)

        let encodedBodyDocument = payload["bodyDocumentJSON"] as? String
        let decodedBodyDocument = encodedBodyDocument
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(RichDocument.self, from: $0) }
        XCTAssertEqual(decodedBodyDocument?.plainText, fullBody)
    }

    func testNoteSnapshotPrefersPlainBodyWhenStructuredDocumentLagsWithoutGrowing() {
        let snapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: nil,
            titleDocument: RichDocument.migrateLegacy("Recovered note"),
            bodyDocument: RichDocument.migrateLegacy("abc"),
            plainBodyText: "xyz"
        )

        XCTAssertEqual(snapshot.bodyPlainText, "xyz")
        XCTAssertEqual(snapshot.bodyDocument.plainText, "xyz")
    }

    func testSyncWriteDispositionUsesUpsertForUnsyncedAtomUpdates() {
        XCTAssertEqual(
            SyncWriteDisposition.resolve(requestedOperation: "UPDATE", serverVersion: 0),
            .upsert
        )
        XCTAssertEqual(
            SyncWriteDisposition.resolve(requestedOperation: "UPDATE", serverVersion: 3),
            .update
        )
    }

    func testCanvasBlockFromNoteAtomCarriesFullBodyAndRichDocuments() {
        let fullBody = Array(repeating: "Performance note body should survive restart.", count: 12)
            .joined(separator: " ")
        let snapshot = RichDocumentPersistence.noteSnapshot(
            existingMetadata: nil,
            titleDocument: RichDocument.migrateLegacy("Ben Call April 12"),
            bodyDocument: RichDocument.migrateLegacy("short preview"),
            plainBodyText: fullBody
        )

        var atom = Atom.new(
            type: .note,
            title: snapshot.atomTitle,
            body: snapshot.atomBody,
            metadata: snapshot.metadata
        )
        atom.id = 42

        let block = CanvasBlock.fromAtom(atom, position: .zero)

        XCTAssertEqual(block.metadata["content"], fullBody)
        XCTAssertEqual(block.metadata["title"], "Ben Call April 12")
        XCTAssertNotNil(block.metadata[RichDocumentMetadataKeys.bodyDocument])
        XCTAssertNotNil(block.metadata[RichDocumentMetadataKeys.titleDocument])
    }

    func testMentionRankingNormalizesSQLiteTimestamps() {
        var atom = Atom.new(type: .note, title: "Recent note")
        atom.updatedAt = "2026-04-22 08:30:15"

        XCTAssertEqual(
            MentionSearchRanking.recencyKey(for: atom),
            "2026-04-22T08:30:15.000Z"
        )
    }

    func testMentionRankingPrefersThinkspaceLastOpenedMetadata() throws {
        let metadata = ThinkspaceMetadata(
            name: "Greenhouse",
            lastOpened: Date(timeIntervalSince1970: 1_776_787_200)
        )
        let metadataString = try XCTUnwrap(
            String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        )

        var atom = Atom.new(type: .thinkspace, title: "Workspace", metadata: metadataString)
        atom.updatedAt = "2026-04-01T10:00:00Z"

        XCTAssertEqual(
            MentionSearchRanking.recencyKey(for: atom),
            "2026-04-21T16:00:00.000Z"
        )
    }

    func testMentionRankingPrefersMoreRecentMatchOverHigherTextScore() {
        let newer = MentionSearchResult(
            atomID: 1,
            atomUUID: "newer",
            atomType: .note,
            entityType: .note,
            title: "Fresh Note",
            subtitle: nil,
            typeLabel: "Note",
            updatedAt: "2026-04-22T09:00:00Z",
            recencyKey: "2026-04-22T09:00:00.000Z",
            score: 50
        )
        let older = MentionSearchResult(
            atomID: 2,
            atomUUID: "older",
            atomType: .note,
            entityType: .note,
            title: "Older Exact Match",
            subtitle: nil,
            typeLabel: "Note",
            updatedAt: "2026-04-20T09:00:00Z",
            recencyKey: "2026-04-20T09:00:00.000Z",
            score: 400
        )

        let sorted = [older, newer].sorted(by: MentionSearchRanking.compare)

        XCTAssertEqual(sorted.map(\.atomUUID), ["newer", "older"])
    }

    // MARK: - Soft line breaks (Shift+Return)

    func testSoftLineBreakRoundTripsInsideOneBlock() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Live in one room\u{2028}Rent the other")])
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document)
        let parsed = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(parsed.blocks.count, 1)
        XCTAssertEqual(parsed.blocks.first?.plainInlineText, "Live in one room\u{2028}Rent the other")
    }

    func testSoftLineBreakInListBlockKeepsSingleBlock() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .bulletList, inlines: [.text("first line\u{2028}second line")])
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document)
        let parsed = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(parsed.blocks.map(\.kind), [.bulletList])
        XCTAssertEqual(parsed.blocks.first?.plainInlineText, "first line\u{2028}second line")
    }

    func testHardNewlinesStillSplitBlocks() {
        let attributed = NSAttributedString(string: "first block\nsecond block")

        let parsed = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(parsed.blocks.count, 2)
        XCTAssertEqual(parsed.blocks.map(\.plainInlineText), ["first block", "second block"])
    }

    func testTrailingHardNewlineProducesEmptyFinalBlock() {
        let attributed = NSAttributedString(string: "only block\n")

        let parsed = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(parsed.blocks.count, 2)
        XCTAssertEqual(parsed.blocks.first?.plainInlineText, "only block")
        XCTAssertEqual(parsed.blocks.last?.plainInlineText, "")
    }

    // MARK: - Checked To-Do Styling (typing-feel pass)

    func testCheckedChecklistRendersStrikethroughButNeverBakesItIntoMarks() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .checklist, inlines: [.text("Ship the polish pass")], checked: true)
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 17)

        // The rendered string visually strikes the content through…
        let contentLocation = (attributed.string as NSString).range(of: "Ship").location
        XCTAssertNotNil(attributed.attribute(.strikethroughStyle, at: contentLocation, effectiveRange: nil))

        // …but parsing back never turns that rendering into a content mark.
        let parsed = RichDocumentSerializer.document(from: attributed)
        XCTAssertEqual(parsed.blocks.first?.kind, .checklist)
        XCTAssertEqual(parsed.blocks.first?.checked, true)
        XCTAssertEqual(parsed.blocks.first?.plainInlineText, "Ship the polish pass")
        let hasStrikeMark = parsed.blocks.first?.inlines.contains { $0.marks.contains(.strikethrough) } ?? false
        XCTAssertFalse(hasStrikeMark)
    }

    func testUncheckedChecklistPreservesGenuineStrikethroughMark() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .checklist, inlines: [.text("Keep my strike", marks: [.strikethrough])], checked: false)
        ])

        let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 17)
        let parsed = RichDocumentSerializer.document(from: attributed)

        XCTAssertEqual(parsed.blocks.first?.checked, false)
        let hasStrikeMark = parsed.blocks.first?.inlines.contains { $0.marks.contains(.strikethrough) } ?? false
        XCTAssertTrue(hasStrikeMark)
    }

    // MARK: - Line-Spacing Rhythm (Aa menu Compact/Standard/Airy)

    func testEditorRhythmPolicyAdjustsBodyLeadingButNotHeadings() {
        let document = RichDocument(blocks: [
            RichBlock(kind: .paragraph, inlines: [.text("Body text")]),
            RichBlock(kind: .heading1, inlines: [.text("Heading text")])
        ])
        let attributed = RichDocumentSerializer.attributedString(from: document, fontSize: 17)

        let airy = EditorRhythmPolicy.applyingLineSpacing(4, to: attributed)

        let nsString = airy.string as NSString
        let bodyStyle = airy.attribute(
            .paragraphStyle,
            at: nsString.range(of: "Body").location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        let headingStyle = airy.attribute(
            .paragraphStyle,
            at: nsString.range(of: "Heading").location,
            effectiveRange: nil
        ) as? NSParagraphStyle

        XCTAssertEqual(bodyStyle?.lineSpacing, 10)  // 6 base + 4 airy
        XCTAssertEqual(headingStyle?.lineSpacing, 4)  // headings keep their own rhythm
    }

    func testEditorRhythmPolicyZeroDeltaIsIdentity() {
        let attributed = RichDocumentSerializer.attributedString(
            from: RichDocument(blocks: [RichBlock(kind: .paragraph, inlines: [.text("Body")])]),
            fontSize: 17
        )
        XCTAssertTrue(EditorRhythmPolicy.applyingLineSpacing(0, to: attributed).isEqual(to: attributed))
    }

    // MARK: - Block Row Rhythm (heading air, list huddle)

    func testBlockRhythmGivesHeadingsAirAboveAndKeepsThemTightBelow() {
        let baseGap: CGFloat = 6  // the standard preset's block gap
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .heading1, following: nil, baseGap: baseGap), 0)
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .heading1, following: .paragraph, baseGap: baseGap), 26)
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .heading2, following: .paragraph, baseGap: baseGap), 21)
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .heading3, following: .paragraph, baseGap: baseGap), 16)
        // Consecutive headings stack closer.
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .heading2, following: .heading1, baseGap: baseGap), 12)
        // The paragraph under a heading hugs it — base gap only.
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .paragraph, following: .heading1, baseGap: baseGap), baseGap)
    }

    func testBlockRhythmHuddlesSameKindListItems() {
        let baseGap: CGFloat = 6
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .bulletList, following: .bulletList, baseGap: baseGap), 4)
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .checklist, following: .checklist, baseGap: baseGap), 4)
        // A list opening after prose keeps the normal gap.
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .bulletList, following: .paragraph, baseGap: baseGap), baseGap)
        // Tight presets never collapse below a readable floor.
        XCTAssertEqual(BlockRhythmPolicy.topSpacing(for: .bulletList, following: .bulletList, baseGap: 4), 4)
    }
}
