import XCTest
@testable import CosmoOS

/// The composer model against a stub host — no database, no
/// `ThinkspaceManager.shared` (its init opens the store).
@MainActor
final class SpaceComposerModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var host: StubSpaceHost!
    private let suiteName = "SpaceComposerModelTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        host = StubSpaceHost()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        host = nil
        super.tearDown()
    }

    private func makeCreateModel(parentId: String? = nil) -> SpaceComposerModel {
        SpaceComposerModel(mode: .create(parentId: parentId), host: host, defaults: defaults)
    }

    // MARK: - Last-used kind

    func testCreateModeNeedsOnlyANameAndOpensItsCanvas() {
        let model = makeCreateModel()

        XCTAssertEqual(model.draft.kind, .custom)
        XCTAssertEqual(model.draft.enabledViews, [.canvas, .library, .deepDive])
        XCTAssertEqual(model.draft.accentColorHex, host.accentHex)
        XCTAssertNil(model.draft.emoji)
        XCTAssertTrue(model.isCreate)
        XCTAssertEqual(model.title, "New space")
        XCTAssertEqual(model.primaryTitle, "Create")
        XCTAssertTrue(model.focusesNameOnAppear)
    }

    func testLegacyKindPreferenceDoesNotConstrainANewSpace() async {
        let first = makeCreateModel()
        first.selectKind(.collection)
        first.draft.name = "Reference dumps"

        let created = await first.commit()

        XCTAssertNotNil(created)
        XCTAssertEqual(defaults.string(forKey: SpaceComposerModel.lastKindDefaultsKey), "collection")

        let second = makeCreateModel()
        XCTAssertEqual(second.draft.kind, .custom)
        XCTAssertEqual(second.draft.enabledViews, [.canvas, .library, .deepDive])
        XCTAssertNil(second.draft.emoji)
    }

    func testRememberedNonComposerKindFallsBack() {
        defaults.set(SpaceKind.client.rawValue, forKey: SpaceComposerModel.lastKindDefaultsKey)
        XCTAssertEqual(makeCreateModel().draft.kind, .custom)

        defaults.set("not-a-kind", forKey: SpaceComposerModel.lastKindDefaultsKey)
        XCTAssertEqual(makeCreateModel().draft.kind, .custom)
    }

    // MARK: - Kind selection

    func testSelectKindAppliesPresetAndSeedsSuggestedEmoji() {
        let model = makeCreateModel()

        model.selectKind(.whiteboard)
        XCTAssertEqual(model.draft.kind, .whiteboard)
        XCTAssertEqual(model.draft.enabledViews, [.canvas])
        XCTAssertEqual(model.draft.emoji, SpaceKind.whiteboard.suggestedEmoji)
        XCTAssertEqual(model.resolvedEmoji, SpaceKind.whiteboard.suggestedEmoji)

        model.selectKind(.project)
        XCTAssertEqual(model.draft.enabledViews, [.library, .canvas, .board])
        XCTAssertEqual(model.openingView, .library)
        XCTAssertEqual(model.draft.emoji, SpaceKind.project.suggestedEmoji)
    }

    func testSelectKindKeepsAnExplicitlyChosenEmoji() {
        let model = makeCreateModel()
        model.setEmoji("🎯")

        model.selectKind(.collection)

        XCTAssertEqual(model.draft.emoji, "🎯")
        XCTAssertTrue(model.emojiIsExplicit)
        XCTAssertFalse(model.isEmojiPickerPresented)
    }

    // MARK: - View toggling

    func testToggleViewKeepsAtLeastOneAndFlipsKindToCustom() {
        let model = makeCreateModel()
        model.selectKind(.whiteboard)

        model.toggleView(.canvas)
        XCTAssertEqual(model.draft.enabledViews, [.canvas], "the last view can't be removed")
        XCTAssertEqual(model.draft.kind, .whiteboard)

        model.toggleView(.library)
        XCTAssertEqual(model.draft.enabledViews, [.canvas, .library])
        XCTAssertEqual(model.draft.kind, .custom)

        model.toggleView(.library)
        XCTAssertEqual(model.draft.enabledViews, [.canvas])
        XCTAssertEqual(model.draft.kind, .custom, "custom never snaps back on its own")
    }

    func testViewChoicesListEnabledRunFirstThenRenderableRest() {
        let model = makeCreateModel()
        model.selectKind(.collection)

        XCTAssertEqual(model.viewChoices, [.library, .canvas, .deepDive])
        XCTAssertTrue(model.isEnabled(.library))
        XCTAssertFalse(model.isEnabled(.deepDive))
    }

    // MARK: - Reordering

    func testMoveViewReordersAndFirstOpens() {
        let model = makeCreateModel()
        model.selectKind(.research)

        model.moveView(.library, before: .deepDive)
        XCTAssertEqual(model.draft.enabledViews, [.library, .deepDive, .canvas])
        XCTAssertEqual(model.openingView, .library)
        XCTAssertEqual(model.draft.kind, .custom, "a reordered preset is a custom shape")

        model.moveView(.deepDive, before: nil)
        XCTAssertEqual(model.draft.enabledViews, [.library, .canvas, .deepDive])
    }

    func testMoveViewEnablesADisabledViewAtThePosition() {
        let model = makeCreateModel()
        model.selectKind(.whiteboard)

        model.moveView(.library, before: .canvas)

        XCTAssertEqual(model.draft.enabledViews, [.library, .canvas])
        XCTAssertEqual(model.openingView, .library)
    }

    func testNudgeViewStepsAlongTheEnabledRun() {
        let model = makeCreateModel()
        model.selectKind(.research)

        model.nudgeView(.canvas, by: -1)
        XCTAssertEqual(model.draft.enabledViews, [.canvas, .deepDive, .library])

        model.nudgeView(.canvas, by: -1)
        XCTAssertEqual(model.draft.enabledViews, [.canvas, .deepDive, .library], "clamped at the front")

        model.nudgeView(.canvas, by: 1)
        model.nudgeView(.canvas, by: 1)
        model.nudgeView(.canvas, by: 1)
        XCTAssertEqual(model.draft.enabledViews, [.deepDive, .library, .canvas], "clamped at the end")

        model.nudgeView(.board, by: 1)
        XCTAssertEqual(model.draft.enabledViews, [.deepDive, .library, .canvas], "a disabled view can't be nudged")
    }

    // MARK: - Validation

    func testValidationMessages() {
        let model = makeCreateModel()

        XCTAssertFalse(model.validation.isValid)
        XCTAssertEqual(model.validation.message, "Give the space a name.")

        model.draft.name = "   "
        XCTAssertEqual(model.validation.message, "Give the space a name.")

        model.draft.name = "Positioning"
        XCTAssertTrue(model.validation.isValid)
        XCTAssertNil(model.validation.message)

        model.draft.enabledViews = []
        XCTAssertEqual(model.validation.message, "Keep at least one view.")
    }

    func testEditModeRefusesACyclicParent() {
        let root = StubSpaceHost.makeThinkspace(name: "Root")
        let child = StubSpaceHost.makeThinkspace(name: "Child", parentId: root.id)
        host.thinkspaces = [root, child]
        let model = SpaceComposerModel(mode: .edit(root), host: host, defaults: defaults)

        XCTAssertEqual(model.title, "Space settings")
        XCTAssertEqual(model.primaryTitle, "Save")
        XCTAssertFalse(model.focusesNameOnAppear)
        XCTAssertTrue(model.validation.isValid)

        model.draft.parentThinkspaceId = child.id
        XCTAssertEqual(model.validation.message, "That space can't contain this one.")
    }

    // MARK: - Identity ladder

    func testResolvedEmojiLadder() {
        let model = makeCreateModel()
        model.selectKind(.research)

        XCTAssertEqual(model.resolvedEmoji, SpaceKind.research.suggestedEmoji, "seeded from the kind")

        model.setEmoji("🎯")
        XCTAssertEqual(model.resolvedEmoji, "🎯", "an explicit pick wins over the seed")

        model.draft.name = "🧪 Lab notes"
        XCTAssertEqual(model.resolvedEmoji, "🧪", "a leading emoji typed into the name always wins")

        model.setEmoji(nil)
        model.draft.name = "Gym log"
        let keywordMark = CollectionEmoji.resolve(name: "Gym log").emoji
        XCTAssertNotNil(keywordMark)
        XCTAssertEqual(model.resolvedEmoji, keywordMark, "a keyword mark beats the kind's suggestion")

        model.draft.name = "Positioning"
        XCTAssertNil(model.resolvedEmoji, "A space does not need a decorative mark")
        XCTAssertNil(model.draft.emoji, "clearing leaves no override in the draft")
    }

    func testEmojiSuggestionsLeadWithTheKindsMark() {
        let model = makeCreateModel()
        model.selectKind(.collection)
        model.draft.name = "Reels to study"

        let suggestions = model.emojiSuggestions
        let nameSuggestions = CollectionEmoji.suggestions(for: "Reels to study")
        XCTAssertEqual(suggestions.first, SpaceKind.collection.suggestedEmoji)
        XCTAssertEqual(
            Array(suggestions.dropFirst()),
            nameSuggestions.filter { $0 != SpaceKind.collection.suggestedEmoji }
        )
        XCTAssertEqual(Set(suggestions).count, suggestions.count, "deduped")
    }

    // MARK: - Commit

    func testCommitPersistsTheMarkTheWellShowed() async {
        let model = makeCreateModel()
        model.selectKind(.research)
        model.setEmoji(nil)
        model.draft.name = "Positioning"

        let created = await model.commit()

        XCTAssertNotNil(created)
        XCTAssertEqual(host.createdDrafts.count, 1)
        XCTAssertNil(host.createdDrafts.first?.emoji, "An undecorated name stays undecorated")
        XCTAssertEqual(host.createdDrafts.first?.name, "Positioning")
    }

    func testCommitLetsATypedEmojiOutrankTheSeed() async {
        let model = makeCreateModel()
        model.selectKind(.research)
        model.draft.name = "🧪 Lab notes"

        _ = await model.commit()

        XCTAssertEqual(host.createdDrafts.first?.emoji, "🧪")
        XCTAssertEqual(host.createdDrafts.first?.name, "Lab notes")
    }

    func testCommitDoesNotFreezeAKeywordMark() async {
        let model = makeCreateModel()
        model.setEmoji(nil)
        model.draft.name = "Gym log"

        _ = await model.commit()

        XCTAssertNil(host.createdDrafts.first?.emoji, "rows derive keyword marks live, so renames keep following")
    }

    func testCommitRefusesAnInvalidDraft() async {
        let model = makeCreateModel()

        let created = await model.commit()

        XCTAssertNil(created)
        XCTAssertTrue(host.createdDrafts.isEmpty)
        XCTAssertNil(defaults.string(forKey: SpaceComposerModel.lastKindDefaultsKey))
    }

    func testCommitPostsDidCreateWithTheDraftsParent() async {
        let parent = StubSpaceHost.makeThinkspace(name: "Parent")
        host.thinkspaces = [parent]
        let model = makeCreateModel(parentId: parent.id)
        model.draft.name = "Nested"

        let received = ReceivedCreation()
        let token = NotificationCenter.default.addObserver(
            forName: CosmoNotification.Navigation.spaceComposerDidCreate,
            object: nil,
            queue: nil
        ) { received.payload = SpaceComposerCreated(from: $0) }
        defer { NotificationCenter.default.removeObserver(token) }

        let created = await model.commit()

        XCTAssertEqual(received.payload?.thinkspaceId, created?.id)
        XCTAssertEqual(received.payload?.parentId, parent.id)
        XCTAssertEqual(model.parentLabel, "Inside · Parent")
    }

    func testEditCommitUpdatesAndReturnsTheRefreshedSpace() async {
        let space = StubSpaceHost.makeThinkspace(name: "Old name", kind: .whiteboard)
        host.thinkspaces = [space]
        let model = SpaceComposerModel(mode: .edit(space), host: host, defaults: defaults)
        model.draft.name = "New name"

        let saved = await model.commit()

        XCTAssertEqual(host.updates.count, 1)
        XCTAssertEqual(host.updates.first?.draft.name, "New name")
        XCTAssertEqual(saved?.name, "New name")
        XCTAssertNil(defaults.string(forKey: SpaceComposerModel.lastKindDefaultsKey), "edits don't touch the remembered kind")
    }

    // MARK: - Parent candidates

    func testParentCandidatesExcludeSelfAndDescendantsInEditMode() {
        let root = StubSpaceHost.makeThinkspace(name: "Root")
        let child = StubSpaceHost.makeThinkspace(name: "Child", parentId: root.id)
        let grandchild = StubSpaceHost.makeThinkspace(name: "Grandchild", parentId: child.id)
        let other = StubSpaceHost.makeThinkspace(name: "Other")
        host.thinkspaces = [root, child, grandchild, other]

        let editing = SpaceComposerModel(mode: .edit(root), host: host, defaults: defaults)
        XCTAssertEqual(editing.parentCandidates.map(\.id), [other.id])

        let creating = makeCreateModel()
        XCTAssertEqual(Set(creating.parentCandidates.map(\.id)), Set([root.id, child.id, grandchild.id, other.id]))
    }

    func testParentOptionsFlattenTheTreeDepthFirstWithDepths() {
        let beta = StubSpaceHost.makeThinkspace(name: "Beta")
        let alpha = StubSpaceHost.makeThinkspace(name: "Alpha")
        let alphaChild = StubSpaceHost.makeThinkspace(name: "Alpha child", parentId: alpha.id)
        host.thinkspaces = [beta, alpha, alphaChild]

        let options = makeCreateModel().parentOptions

        XCTAssertEqual(options.map(\.thinkspace.name), ["Alpha", "Alpha child", "Beta"])
        XCTAssertEqual(options.map(\.depth), [0, 1, 0])
    }

    func testClientSpacesKeepTheirKindWhenViewsChange() {
        let client = StubSpaceHost.makeThinkspace(name: "Acme", kind: .client, enabledViews: SpaceKind.client.preset.views)
        host.thinkspaces = [client]
        let model = SpaceComposerModel(mode: .edit(client), host: host, defaults: defaults)

        model.toggleView(.deepDive)

        XCTAssertEqual(model.draft.kind, .client)
        XCTAssertTrue(model.draft.enabledViews.contains(.deepDive))
    }
}

// MARK: - Test helpers

/// Reference box so the notification observer needn't capture a mutable local.
private final class ReceivedCreation: @unchecked Sendable {
    var payload: SpaceComposerCreated?
}

// MARK: - Stub host

@MainActor
private final class StubSpaceHost: SpaceComposerHost {
    var thinkspaces: [Thinkspace] = []
    var accentHex = "#4A7B9D"
    var createdDrafts: [SpaceDraft] = []
    var updates: [(thinkspace: Thinkspace, draft: SpaceDraft)] = []

    var sidebarThinkspaces: [Thinkspace] { thinkspaces }

    func suggestedAccentColorHex() -> String { accentHex }

    /// Mirrors the manager: never self, never a descendant.
    func canNest(_ thinkspaceId: String, under newParentId: String) -> Bool {
        guard thinkspaceId != newParentId else { return false }
        var current: String? = newParentId
        var visited = Set<String>()
        while let id = current {
            if id == thinkspaceId { return false }
            guard visited.insert(id).inserted else { break }
            current = thinkspaces.first { $0.id == id }?.parentThinkspaceId
        }
        return true
    }

    func createThinkspace(draft: SpaceDraft, projectUuid: String?, isRoot: Bool) async -> Thinkspace? {
        createdDrafts.append(draft)
        let created = Self.makeThinkspace(
            name: draft.name,
            kind: draft.kind,
            emoji: draft.emoji,
            parentId: draft.parentThinkspaceId,
            enabledViews: draft.enabledViews
        )
        thinkspaces.append(created)
        return created
    }

    func updateSpaceSettings(_ thinkspace: Thinkspace, draft: SpaceDraft) async {
        updates.append((thinkspace, draft))
        guard let index = thinkspaces.firstIndex(where: { $0.id == thinkspace.id }) else { return }
        thinkspaces[index].name = draft.name
        thinkspaces[index].kind = draft.kind
        thinkspaces[index].emoji = draft.emoji
        thinkspaces[index].enabledViews = draft.enabledViews
        thinkspaces[index].parentThinkspaceId = draft.parentThinkspaceId
    }

    /// A thinkspace from an in-memory atom — no store involved.
    static func makeThinkspace(
        name: String,
        kind: SpaceKind = .custom,
        emoji: String? = nil,
        parentId: String? = nil,
        enabledViews: [SpaceView] = SpaceView.legacyDefault
    ) -> Thinkspace {
        let metadata = ThinkspaceMetadata(
            name: name,
            parentThinkspaceId: parentId,
            kind: kind.rawValue,
            emoji: emoji,
            enabledViews: enabledViews.map(\.rawValue),
            defaultView: enabledViews.first?.rawValue
        )
        let json = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        return Thinkspace(from: Atom.new(type: .thinkspace, title: name, metadata: json))
    }
}
