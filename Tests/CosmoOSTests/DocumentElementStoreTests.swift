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

    func testSlashCommandCatalogUsesSingleElementsParentInDefaultMenu() throws {
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

        XCTAssertEqual(commands.filter { $0.type == .elements }.map(\.title), ["Elements"])
        XCTAssertFalse(commands.contains { $0.type == .newElement })
        XCTAssertFalse(commands.contains { $0.type == .element })

        let submenuCommands = SlashCommandCatalog.elementSubmenuCommands(elementDefinitions: [disabled, audience])
        XCTAssertEqual(submenuCommands.map(\.title), ["New Element", "Target Audience"])
        XCTAssertEqual(submenuCommands.last?.type, .element)
        XCTAssertEqual(submenuCommands.last?.icon, "person.2.fill")
        XCTAssertEqual(submenuCommands.last?.elementDefinition?.id, audience.id)
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
