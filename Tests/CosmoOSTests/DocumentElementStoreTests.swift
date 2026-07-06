import XCTest
@testable import CosmoOS

@MainActor
final class DocumentElementStoreTests: XCTestCase {
    func testCreateSearchUpdateAndSoftDeleteDefinitions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("Elements.json")
        let store = DocumentElementStore(fileURL: fileURL)

        let audience = try store.createDefinition(title: "Audience", systemIcon: "person.2.fill")
        _ = try store.createDefinition(title: "Offer Stack", systemIcon: "square.stack.3d.up")

        XCTAssertEqual(store.activeDefinitions.map(\.title), ["Audience", "Offer Stack"])
        XCTAssertEqual(store.search("aud").map(\.id), [audience.id])

        let updated = try store.updateDefinition(
            id: audience.id,
            title: "Target Audience",
            systemIcon: "target"
        )

        XCTAssertEqual(updated.title, "Target Audience")
        XCTAssertEqual(updated.systemIcon, "target")
        XCTAssertEqual(store.search("audience").first?.id, audience.id)

        try store.disableDefinition(id: audience.id)
        XCTAssertFalse(store.activeDefinitions.contains { $0.id == audience.id })
        XCTAssertFalse(store.search("audience").contains { $0.id == audience.id })
    }

    func testStoreRecoversFromCorruptJSONByStartingEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("Elements.json")
        try Data("not json".utf8).write(to: fileURL)

        let store = DocumentElementStore(fileURL: fileURL)

        XCTAssertEqual(store.activeDefinitions, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .contains { $0.lastPathComponent.hasPrefix("Elements.corrupt-") })
    }

    func testSlashCommandCatalogRendersElementsInlineWithNewElementLast() throws {
        let disabled = DocumentElementDefinition(
            title: "Archived",
            systemIcon: "archivebox",
            isEnabled: false
        )
        let audience = DocumentElementDefinition(
            title: "Target Audience",
            systemIcon: "person.2.fill"
        )

        let commands = SlashCommandCatalog.commands(elementDefinitions: [disabled, audience])

        // Elements render inline as their own section — no flyout parent row.
        XCTAssertFalse(commands.contains { $0.type == .elements })
        let elementRows = commands.filter { $0.section == .elements }
        XCTAssertEqual(elementRows.map(\.title), ["Target Audience", "New Element…"])
        XCTAssertEqual(elementRows.first?.elementDefinition?.id, audience.id)
        XCTAssertFalse(elementRows.contains { $0.isStarterElement })
    }

    func testSlashCommandCatalogOffersStarterGalleryWhenNoElementsExist() throws {
        let commands = SlashCommandCatalog.commands(elementDefinitions: [])
        let elementRows = commands.filter { $0.section == .elements }

        XCTAssertEqual(elementRows.dropLast().count, SlashCommandCatalog.starterDefinitions.count)
        XCTAssertTrue(elementRows.dropLast().allSatisfy(\.isStarterElement))
        XCTAssertEqual(elementRows.last?.type, .newElement)
        // Starters carry template structure and deterministic ids.
        XCTAssertTrue(SlashCommandCatalog.starterDefinitions.allSatisfy { !$0.templateChildren.isEmpty })
        XCTAssertEqual(
            Set(SlashCommandCatalog.starterDefinitions.map(\.id)).count,
            SlashCommandCatalog.starterDefinitions.count
        )
    }

    func testStarterAdoptionPreservesIdentityAndTemplate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("Elements.json")
        let store = DocumentElementStore(fileURL: fileURL)

        let starter = SlashCommandCatalog.starterDefinitions[0]
        try store.adopt(starter)
        try store.adopt(starter) // second adopt is a no-op

        XCTAssertEqual(store.definitions.count, 1)
        XCTAssertEqual(store.definitions[0].id, starter.id)
        XCTAssertEqual(store.definitions[0].templateChildren.count, starter.templateChildren.count)
    }

    func testElementInsertionStampsTintAndTemplateChildren() throws {
        let definition = DocumentElementDefinition(
            title: "Decision",
            systemIcon: "scale.3d",
            tintID: "clay",
            templateChildren: [RichBlock(kind: .checklist, inlines: [.text("Option")], checked: false)]
        )

        let block = RichBlock.element(definition)

        XCTAssertEqual(block.element?.tintSnapshot, "clay")
        XCTAssertEqual(block.children.count, 1)
        XCTAssertEqual(block.children[0].kind, .checklist)
        // Template copies get fresh identity.
        XCTAssertNotEqual(block.children[0].id, definition.templateChildren[0].id)
    }

    func testSlashCommandCatalogSearchMatchesElementNames() throws {
        let audience = DocumentElementDefinition(
            title: "Target Audience",
            systemIcon: "person.2.fill"
        )
        let offer = DocumentElementDefinition(
            title: "Offer Stack",
            systemIcon: "square.stack.3d.up"
        )

        let commands = SlashCommandCatalog.filteredCommands(
            matching: "aud",
            elementDefinitions: [offer, audience]
        )

        XCTAssertEqual(commands.map(\.title), ["Target Audience"])

        let newElementCommands = SlashCommandCatalog.filteredCommands(
            matching: "new element",
            elementDefinitions: [offer, audience]
        )

        XCTAssertEqual(newElementCommands.first?.type, .newElement)
    }
}
