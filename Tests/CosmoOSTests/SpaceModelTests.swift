import XCTest
import AppKit
@testable import CosmoOS

/// The space shape: raw metadata → resolved views, the opening ladder, kind
/// presets, draft normalisation, and the two pure shell policies.
final class SpaceModelTests: XCTestCase {

    // MARK: - Resolver

    func testLegacyMetadataResolvesToThreeViewsOpeningOnCanvas() {
        let views = SpaceViewResolver.enabledViews(raw: nil, kind: nil)
        XCTAssertEqual(views, [.canvas, .library, .deepDive])
        let opening = SpaceViewResolver.openingView(
            renderable: SpaceViewResolver.renderableViews(views),
            lastRaw: nil,
            defaultRaw: nil,
            kind: nil
        )
        XCTAssertEqual(opening, .canvas)
    }

    func testUnknownRawValuesAreDroppedNotFatal() {
        let views = SpaceViewResolver.enabledViews(raw: ["canvas", "hologram", "library", "canvas"], kind: .research)
        XCTAssertEqual(views, [.canvas, .library], "unknown raws vanish, duplicates collapse, order survives")
        XCTAssertNil(SpaceKind(rawValue: "moodboard"))
    }

    func testEmptyRawFallsBackToKindPresetThenLegacy() {
        XCTAssertEqual(SpaceViewResolver.enabledViews(raw: [], kind: .whiteboard), [.canvas])
        XCTAssertEqual(SpaceViewResolver.enabledViews(raw: ["nope"], kind: nil), SpaceView.legacyDefault)
    }

    func testRenderableViewsNeverEmpty() {
        // Calendar and Tasks views are deferred (no surface yet); Board has one since phase 3.
        XCTAssertEqual(SpaceViewResolver.renderableViews([.calendar, .tasks]), [.home, .library, .canvas, .deepDive])
        XCTAssertEqual(SpaceViewResolver.renderableViews([.library, .tasks, .canvas]), [.home, .library, .canvas, .deepDive])
        XCTAssertEqual(SpaceViewResolver.renderableViews([.board, .calendar]), [.home, .library, .canvas, .deepDive])
    }

    func testOpeningLadderLastThenDefaultThenKindThenFirst() {
        let renderable: [SpaceView] = [.library, .canvas]
        XCTAssertEqual(
            SpaceViewResolver.openingView(renderable: renderable, lastRaw: "canvas", defaultRaw: "library", kind: .collection),
            .canvas, "last visited wins while it is still renderable"
        )
        XCTAssertEqual(
            SpaceViewResolver.openingView(renderable: renderable, lastRaw: "deepDive", defaultRaw: "library", kind: .collection),
            .library, "a disabled last view yields to the preferred one"
        )
        XCTAssertEqual(
            SpaceViewResolver.openingView(renderable: renderable, lastRaw: nil, defaultRaw: "deepDive", kind: .collection),
            .library, "a disabled preferred view yields to the kind"
        )
        XCTAssertEqual(
            SpaceViewResolver.openingView(renderable: [.canvas], lastRaw: nil, defaultRaw: nil, kind: .research),
            .canvas, "a kind whose opener is disabled yields to the first renderable view"
        )
    }

    func testEveryKindOpensOnOneOfItsOwnViews() {
        for kind in SpaceKind.allCases {
            XCTAssertTrue(kind.preset.views.contains(kind.preset.opens), "\(kind) opens on a view it does not enable")
            XCTAssertFalse(kind.preset.views.isEmpty)
        }
        XCTAssertEqual(SpaceKind.research.preset.opens, .deepDive)
        XCTAssertEqual(SpaceKind.whiteboard.preset.views, [.canvas])
        XCTAssertEqual(SpaceKind.collection.preset.opens, .library)
    }

    // MARK: - Metadata coding

    func testLegacyMetadataJSONDecodesWithNilShape() throws {
        let json = """
        {"name":"Pranayama","lastOpened":0,"zoomLevel":1,"panOffsetX":0,"panOffsetY":0,"blockIds":["a"],"isRootThinkspace":false}
        """
        let metadata = try JSONDecoder().decode(ThinkspaceMetadata.self, from: Data(json.utf8))
        XCTAssertNil(metadata.kind)
        XCTAssertNil(metadata.enabledViews)
        XCTAssertNil(metadata.lastView)
        let atom = Atom.new(type: .thinkspace, title: "Pranayama", metadata: json)
        let space = Thinkspace(from: atom)
        XCTAssertNil(space.kind)
        XCTAssertEqual(space.enabledViews, SpaceView.legacyDefault)
        XCTAssertEqual(space.openingView, .canvas)
    }

    func testShapeRoundTripsThroughMetadata() throws {
        let metadata = ThinkspaceMetadata(
            name: "Goals",
            kind: SpaceKind.whiteboard.rawValue,
            emoji: "🗺️",
            enabledViews: [SpaceView.canvas.rawValue],
            defaultView: SpaceView.canvas.rawValue,
            lastView: SpaceView.canvas.rawValue,
            linkedClientUUID: "client-1"
        )
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(ThinkspaceMetadata.self, from: data)
        XCTAssertEqual(decoded.kind, "whiteboard")
        XCTAssertEqual(decoded.emoji, "🗺️")
        XCTAssertEqual(decoded.enabledViews, ["canvas"])
        XCTAssertEqual(decoded.linkedClientUUID, "client-1")

        let atom = Atom.new(type: .thinkspace, title: "Goals", metadata: String(data: data, encoding: .utf8))
        let space = Thinkspace(from: atom)
        XCTAssertEqual(space.kind, .whiteboard)
        XCTAssertEqual(space.renderableViews, [.home, .library, .canvas, .deepDive])
        XCTAssertEqual(space.openingView, .canvas)
        XCTAssertEqual(space.identityEmoji, "🗺️")
    }

    func testUnknownKindInMetadataDoesNotBreakDecode() throws {
        let json = """
        {"name":"X","lastOpened":0,"zoomLevel":1,"panOffsetX":0,"panOffsetY":0,"blockIds":[],"kind":"moodboard","enabledViews":["canvas","hologram"],"clusters":[]}
        """
        let atom = Atom.new(type: .thinkspace, title: "X", metadata: json)
        let space = Thinkspace(from: atom)
        XCTAssertNil(space.kind)
        XCTAssertEqual(space.enabledViews, [.canvas])
    }

    func testThinkspaceEqualityIncludesShape() throws {
        let a = ThinkspaceMetadata(name: "A", enabledViews: ["canvas"], lastView: "canvas")
        var b = a
        b.lastView = "library"
        let atomA = Atom.new(type: .thinkspace, title: "A", metadata: String(data: try JSONEncoder().encode(a), encoding: .utf8))
        var atomB = Atom.new(type: .thinkspace, title: "A", metadata: String(data: try JSONEncoder().encode(b), encoding: .utf8))
        atomB.uuid = atomA.uuid
        XCTAssertNotEqual(Thinkspace(from: atomA), Thinkspace(from: atomB))
    }

    // MARK: - Draft

    func testDraftNormalizationLiftsLeadingEmojiAndTrims() {
        var draft = SpaceDraft.new(kind: .research, accentHex: "#2D6A4F")
        draft.name = "  🔬 Pranayama "
        let normalized = draft.normalized()
        XCTAssertEqual(normalized.name, "Pranayama")
        XCTAssertEqual(normalized.emoji, "🔬")
    }

    func testDraftValidation() {
        var draft = SpaceDraft.new(kind: .research, accentHex: "#2D6A4F")
        XCTAssertFalse(draft.validate(canNest: { _ in true }).isValid)
        draft.name = "Pranayama"
        XCTAssertTrue(draft.validate(canNest: { _ in true }).isValid)
        draft.enabledViews = []
        XCTAssertFalse(draft.validate(canNest: { _ in true }).isValid)
        draft.enabledViews = [.canvas]
        draft.parentThinkspaceId = "parent"
        XCTAssertFalse(draft.validate(canNest: { _ in false }).isValid)
    }

    func testProgrammaticDefaultKeepsTodaysShape() {
        let draft = SpaceDraft.programmaticDefault(name: "Inbox space", accentHex: "#2D6A4F")
        XCTAssertEqual(draft.kind, .custom)
        XCTAssertEqual(draft.enabledViews, [.home, .library, .canvas, .deepDive])
        XCTAssertEqual(draft.defaultView, .home)
    }

    // MARK: - Keyboard policy

    func testCommandDigitSelectsViewWithinEnabledCount() {
        XCTAssertEqual(viewIndex(keyCode: 19, modifiers: .command, count: 3), 1)
        XCTAssertNil(viewIndex(keyCode: 21, modifiers: .command, count: 3), "⌘4 with three views is not ours")
        XCTAssertNil(viewIndex(keyCode: 19, modifiers: [.command, .shift], count: 3))
        XCTAssertNil(viewIndex(keyCode: 19, modifiers: [.command, .option], count: 3))
        XCTAssertNil(viewIndex(keyCode: 19, modifiers: .control, count: 3))
    }

    func testCommandDigitYieldsWhileTypingOrInFocusOrCommandK() {
        XCTAssertNil(viewIndex(keyCode: 18, modifiers: .command, count: 3, typing: true))
        XCTAssertNil(viewIndex(keyCode: 18, modifiers: .command, count: 3, focused: true))
        XCTAssertNil(viewIndex(keyCode: 18, modifiers: .command, count: 3, commandK: true))
        XCTAssertNil(viewIndex(keyCode: 18, modifiers: .command, count: 3, thinkspaceActive: false))
    }

    private func viewIndex(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        count: Int,
        typing: Bool = false,
        focused: Bool = false,
        commandK: Bool = false,
        thinkspaceActive: Bool = true
    ) -> Int? {
        SpaceKeyboardShortcutPolicy.viewIndex(
            keyCode: keyCode,
            modifiers: modifiers,
            enabledCount: count,
            isThinkspaceActive: thinkspaceActive,
            hasFocusedEntity: focused,
            isCommandKVisible: commandK,
            isTextInputFocused: typing
        )
    }

    // MARK: - Deep dive routing policy

    private func space(_ id: String, profile: String?, views: [String]) throws -> Thinkspace {
        let metadata = ThinkspaceMetadata(name: id, deepDiveProfileUUID: profile, enabledViews: views)
        var atom = Atom.new(type: .thinkspace, title: id, metadata: String(data: try JSONEncoder().encode(metadata), encoding: .utf8))
        atom.uuid = id
        return Thinkspace(from: atom)
    }

    func testProfileDiveRedirectsIntoItsSpaceWhenViewEnabled() throws {
        let home = try space("home", profile: "dive-1", views: ["deepDive", "canvas"])
        let redirect = SpaceDeepDiveRoutingPolicy.spaceRedirect(deepDiveUUID: "dive-1", primaryThinkspaceUUID: "home", thinkspaces: [home])
        XCTAssertEqual(redirect, .init(thinkspaceId: "home"))
    }

    func testProfileDiveRemainsAvailableRegardlessOfLegacyViewConfiguration() throws {
        let home = try space("home", profile: "dive-1", views: ["canvas"])
        XCTAssertEqual(SpaceDeepDiveRoutingPolicy.spaceRedirect(deepDiveUUID: "dive-1", primaryThinkspaceUUID: "home", thinkspaces: [home]), .init(thinkspaceId: "home"))
    }

    func testSecondaryDiveNeverRedirects() throws {
        let home = try space("home", profile: "dive-1", views: ["deepDive", "canvas"])
        XCTAssertNil(SpaceDeepDiveRoutingPolicy.spaceRedirect(deepDiveUUID: "dive-2", primaryThinkspaceUUID: "home", thinkspaces: [home]))
    }

    func testDiveWithUnrecordedProfileUsesPrimaryHome() throws {
        let home = try space("home", profile: nil, views: ["deepDive"])
        XCTAssertEqual(
            SpaceDeepDiveRoutingPolicy.spaceRedirect(deepDiveUUID: "dive-9", primaryThinkspaceUUID: "home", thinkspaces: [home]),
            .init(thinkspaceId: "home")
        )
        XCTAssertNil(SpaceDeepDiveRoutingPolicy.spaceRedirect(deepDiveUUID: "dive-9", primaryThinkspaceUUID: "elsewhere", thinkspaces: [home]))
    }
}
