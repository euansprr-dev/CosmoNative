import XCTest
@testable import CosmoOS

final class BlockCommandCatalogTests: XCTestCase {
    func testBaseCommandsContainAllBlockTypesShownInSlashMenu() {
        let commands = BlockCommandCatalog.baseCommands

        XCTAssertTrue(commands.contains { $0.action == .transformHeading(.heading1, collapsible: false) })
        XCTAssertTrue(commands.contains { $0.action == .transformHeading(.heading2, collapsible: false) })
        XCTAssertTrue(commands.contains { $0.action == .transformHeading(.heading3, collapsible: false) })
        XCTAssertTrue(commands.contains { $0.action == .transformHeading(.heading1, collapsible: true) })
        XCTAssertTrue(commands.contains { $0.action == .transformHeading(.heading2, collapsible: true) })
        XCTAssertTrue(commands.contains { $0.action == .transformHeading(.heading3, collapsible: true) })
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

    func testSlashCommandMappingRoutesBlockTransformationsThroughBlockEditor() {
        XCTAssertEqual(BlockCommandCatalog.action(for: .heading1), .transformHeading(.heading1, collapsible: false))
        XCTAssertEqual(BlockCommandCatalog.action(for: .heading2), .transformHeading(.heading2, collapsible: false))
        XCTAssertEqual(BlockCommandCatalog.action(for: .heading3), .transformHeading(.heading3, collapsible: false))
        XCTAssertEqual(BlockCommandCatalog.action(for: .toggleHeading1), .transformHeading(.heading1, collapsible: true))
        XCTAssertEqual(BlockCommandCatalog.action(for: .toggleHeading2), .transformHeading(.heading2, collapsible: true))
        XCTAssertEqual(BlockCommandCatalog.action(for: .toggleHeading3), .transformHeading(.heading3, collapsible: true))
        XCTAssertEqual(BlockCommandCatalog.action(for: .quote), .transform(.quote))
        XCTAssertEqual(BlockCommandCatalog.action(for: .bulletList), .transform(.bulletList))
        XCTAssertEqual(BlockCommandCatalog.action(for: .numberedList), .transform(.numberedList))
        XCTAssertEqual(BlockCommandCatalog.action(for: .checkbox), .transform(.checklist))
        XCTAssertEqual(BlockCommandCatalog.action(for: .divider), .replaceOrInsert(.divider))
        XCTAssertEqual(BlockCommandCatalog.action(for: .content), .replaceOrInsert(.content))
        XCTAssertEqual(BlockCommandCatalog.action(for: .research), .replaceOrInsert(.research))
        XCTAssertNil(BlockCommandCatalog.action(for: .image))
        XCTAssertNil(BlockCommandCatalog.action(for: .writingAI))
    }

    func testCommandActionNamesAreNativeUndoLabels() {
        XCTAssertEqual(BlockCommand.Action.transform(.heading1).undoActionName, "Transform to Heading 1")
        XCTAssertEqual(BlockCommand.Action.transformHeading(.heading1, collapsible: false).undoActionName, "Transform to Heading 1")
        XCTAssertEqual(BlockCommand.Action.transformHeading(.heading2, collapsible: true).undoActionName, "Transform to Toggle Heading 2")
        XCTAssertEqual(BlockCommand.Action.replaceOrInsert(.divider).undoActionName, "Insert Divider")
        XCTAssertEqual(BlockCommand.Action.replaceOrInsert(.content).undoActionName, "Insert Content Block")
    }
}
