import AppKit
import Combine
import Foundation

enum DocumentElementSymbol {
    static let fallback = "square.grid.2x2"

    static func validName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) == nil ? fallback : trimmed
    }
}

struct DocumentElementDefinition: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var title: String
    var systemIcon: String
    var createdAt: Date
    var updatedAt: Date
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String,
        systemIcon: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.systemIcon = systemIcon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEnabled = isEnabled
    }
}

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
        instanceTitleSnapshot: String? = nil
    ) {
        self.id = id
        self.definitionID = definitionID
        self.titleSnapshot = Self.normalized(titleSnapshot, fallback: "Untitled Element")
        self.systemIconSnapshot = DocumentElementSymbol.validName(systemIconSnapshot)
        self.isCollapsed = isCollapsed
        self.instanceTitleSnapshot = Self.normalized(instanceTitleSnapshot ?? titleSnapshot, fallback: self.titleSnapshot)
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
        titleSnapshot = Self.normalized(
            try container.decodeIfPresent(String.self, forKey: .titleSnapshot),
            fallback: "Untitled Element"
        )
        systemIconSnapshot = DocumentElementSymbol.validName(
            try container.decodeIfPresent(String.self, forKey: .systemIconSnapshot) ?? DocumentElementSymbol.fallback
        )
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        instanceTitleSnapshot = Self.normalized(
            try container.decodeIfPresent(String.self, forKey: .instanceTitleSnapshot),
            fallback: titleSnapshot
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(definitionID, forKey: .definitionID)
        try container.encode(titleSnapshot, forKey: .titleSnapshot)
        try container.encode(systemIconSnapshot, forKey: .systemIconSnapshot)
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try container.encode(instanceTitleSnapshot, forKey: .instanceTitleSnapshot)
    }

    private static func normalized(_ value: String?, fallback: String) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

enum DocumentElementRendering {
    static func title(for block: RichBlock) -> String {
        block.element?.titleSnapshot ?? "Untitled Element"
    }

    static func instanceTitle(for block: RichBlock) -> String {
        block.element?.instanceTitleSnapshot ?? title(for: block)
    }

    static func systemIcon(for block: RichBlock) -> String {
        DocumentElementSymbol.validName(block.element?.systemIconSnapshot ?? DocumentElementSymbol.fallback)
    }

    static func isCollapsed(_ block: RichBlock) -> Bool {
        block.element?.isCollapsed ?? false
    }

    static func visibleChildBlocks(for block: RichBlock) -> [RichBlock] {
        guard block.kind == .element, !isCollapsed(block) else { return [] }
        return block.children
    }
}

struct DocumentElementHeaderLayout: Equatable {
    var chromeRect: CGRect
    var chevronHitRect: CGRect
    var chevronGlyphRect: CGRect
    var iconRect: CGRect
    var titleRect: CGRect

    static let headerHeight: CGFloat = 38
    static let chevronWidth: CGFloat = 22
    static let iconSize: CGFloat = 14
    static let leadingPadding: CGFloat = 12
    static let nestedIndent: CGFloat = 16

    init(
        chromeRect: CGRect,
        headerMidY: CGFloat,
        depth: Int,
        fontSize: CGFloat
    ) {
        let nestedInset = CGFloat(max(0, depth)) * Self.nestedIndent
        let chevronHitRect = CGRect(
            x: chromeRect.minX + Self.leadingPadding + nestedInset,
            y: headerMidY - (Self.headerHeight / 2),
            width: Self.chevronWidth,
            height: Self.headerHeight
        )
        let iconRect = CGRect(
            x: chevronHitRect.maxX + 2,
            y: headerMidY - (Self.iconSize / 2),
            width: Self.iconSize,
            height: Self.iconSize
        )
        let titleX = iconRect.maxX + 8

        self.chromeRect = chromeRect
        self.chevronHitRect = chevronHitRect
        self.chevronGlyphRect = CGRect(
            x: chevronHitRect.midX - 4,
            y: headerMidY - 4,
            width: 8,
            height: 8
        )
        self.iconRect = iconRect
        self.titleRect = CGRect(
            x: titleX,
            y: headerMidY - 9,
            width: max(80, chromeRect.maxX - titleX - Self.leadingPadding),
            height: 18
        )
    }

    static func titleLeadingInset(depth: Int, fontSize: CGFloat) -> CGFloat {
        let layout = DocumentElementHeaderLayout(
            chromeRect: CGRect(x: 0, y: 0, width: 720, height: headerHeight),
            headerMidY: headerHeight / 2,
            depth: depth,
            fontSize: fontSize
        )
        return layout.titleRect.minX
    }
}

enum DocumentElementMutation {
    static func toggledCollapse(instanceID: UUID, in document: RichDocument) -> RichDocument {
        RichDocument(blocks: toggledCollapse(instanceID: instanceID, in: document.blocks))
    }

    private static func toggledCollapse(instanceID: UUID, in blocks: [RichBlock]) -> [RichBlock] {
        blocks.map { block in
            var updated = block
            if updated.element?.id == instanceID {
                updated.element?.isCollapsed.toggle()
                return updated
            }
            if !updated.children.isEmpty {
                updated.children = toggledCollapse(instanceID: instanceID, in: updated.children)
            }
            return updated
        }
    }
}

struct DocumentElementEditorDecoration: Equatable {
    var range: NSRange
    var blockRange: NSRange
    var instanceID: UUID?
    var title: String
    var instanceTitle: String
    var systemIcon: String
    var isCollapsed: Bool
    var depth: Int

    static func decorations(in attributedString: NSAttributedString) -> [DocumentElementEditorDecoration] {
        guard attributedString.length > 0 else { return [] }

        var decorations: [DocumentElementEditorDecoration] = []
        let fullString = attributedString.string as NSString
        var lineStart = 0

        while lineStart < attributedString.length {
            let lineRange = fullString.lineRange(for: NSRange(location: lineStart, length: 0))
            let safeRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: attributedString.length))
            let trimmedRange = trimmingTrailingNewline(from: safeRange, in: fullString)

            if trimmedRange.length > 0,
               let definitionID = attributedString.attribute(
                RichDocumentAttributeKeys.elementDefinitionID,
                at: trimmedRange.location,
                effectiveRange: nil
               ) as? String,
               UUID(uuidString: definitionID) != nil {
                decorations.append(decoration(
                    in: attributedString,
                    string: fullString,
                    range: trimmedRange,
                    blockRange: blockRange(
                        from: lineRange,
                        parentDepth: intValue(attributedString.attribute(
                            RichDocumentAttributeKeys.elementDepth,
                            at: trimmedRange.location,
                            effectiveRange: nil
                        )) ?? 0,
                        attributedString: attributedString,
                        string: fullString
                    )
                ))
            }

            lineStart = lineRange.location + lineRange.length
            if lineStart <= safeRange.location {
                break
            }
        }

        return decorations
    }

    private static func decoration(
        in attributedString: NSAttributedString,
        string: NSString,
        range: NSRange,
        blockRange: NSRange
    ) -> DocumentElementEditorDecoration {
        let title = attributedString.attribute(
            RichDocumentAttributeKeys.elementTitle,
            at: range.location,
            effectiveRange: nil
        ) as? String
        let icon = attributedString.attribute(
            RichDocumentAttributeKeys.elementIcon,
            at: range.location,
            effectiveRange: nil
        ) as? String
        let instanceTitle = attributedString.attribute(
            RichDocumentAttributeKeys.elementInstanceTitle,
            at: range.location,
            effectiveRange: nil
        ) as? String
        let instanceID = uuidValue(attributedString.attribute(
            RichDocumentAttributeKeys.elementInstanceID,
            at: range.location,
            effectiveRange: nil
        ))
        let collapsedValue = attributedString.attribute(
            RichDocumentAttributeKeys.elementCollapsed,
            at: range.location,
            effectiveRange: nil
        )
        let depthValue = attributedString.attribute(
            RichDocumentAttributeKeys.elementDepth,
            at: range.location,
            effectiveRange: nil
        )

        return DocumentElementEditorDecoration(
            range: range,
            blockRange: blockRange,
            instanceID: instanceID,
            title: (title ?? string.substring(with: range)).trimmingCharacters(in: .whitespacesAndNewlines),
            instanceTitle: (instanceTitle ?? string.substring(with: range)).trimmingCharacters(in: .whitespacesAndNewlines),
            systemIcon: DocumentElementSymbol.validName(icon ?? DocumentElementSymbol.fallback),
            isCollapsed: boolValue(collapsedValue) ?? false,
            depth: max(0, intValue(depthValue) ?? 0)
        )
    }

    private static func blockRange(
        from headerLineRange: NSRange,
        parentDepth: Int,
        attributedString: NSAttributedString,
        string: NSString
    ) -> NSRange {
        var result = headerLineRange
        var cursor = headerLineRange.location + headerLineRange.length

        while cursor < attributedString.length {
            let lineRange = string.lineRange(for: NSRange(location: cursor, length: 0))
            let safeRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: attributedString.length))
            let trimmedRange = trimmingTrailingNewline(from: safeRange, in: string)

            guard trimmedRange.length > 0 else {
                cursor = lineRange.location + lineRange.length
                continue
            }

            let depth = intValue(attributedString.attribute(
                RichDocumentAttributeKeys.elementDepth,
                at: trimmedRange.location,
                effectiveRange: nil
            )) ?? 0
            guard depth > parentDepth else { break }

            result = NSUnionRange(result, lineRange)
            cursor = lineRange.location + lineRange.length
        }

        return result
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

enum DocumentElementContextFormatter {
    static func contextBody(for atom: Atom) -> String {
        guard let document = richBodyDocument(for: atom) else {
            return atom.body ?? ""
        }

        let formatted = contextText(for: document)
        let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (atom.body ?? "") : trimmed
    }

    static func contextText(for document: RichDocument) -> String {
        lines(for: document.blocks, depth: 0).joined(separator: "\n")
    }

    private static func richBodyDocument(for atom: Atom) -> RichDocument? {
        RichDocumentMetadataStorage.readDocument(
            from: atom.metadata,
            key: RichDocumentMetadataKeys.bodyDocument
        )
        ?? RichDocumentMetadataStorage.readDocument(
            from: atom.metadata,
            key: RichDocumentMetadataKeys.contentDraftDocument
        )
    }

    private static func lines(for blocks: [RichBlock], depth: Int) -> [String] {
        blocks.enumerated().flatMap { index, block in
            lines(for: block, in: blocks, at: index, depth: depth)
        }
    }

    private static func lines(
        for block: RichBlock,
        in siblings: [RichBlock],
        at index: Int,
        depth: Int
    ) -> [String] {
        let indentation = String(repeating: "  ", count: depth)

        switch block.kind {
        case .divider:
            return ["\(indentation)<divider />"]
        case .image:
            return ["\(indentation)[Image]"]
        case .element:
            let title = block.element?.titleSnapshot ?? "Untitled Element"
            let instanceTitle = block.element?.instanceTitleSnapshot ?? title
            let icon = block.element?.systemIconSnapshot ?? "square.dashed"
            let collapsed = block.element?.isCollapsed ?? false
            var output = [
                "\(indentation)<element title=\"\(escapedAttribute(title))\" icon=\"\(escapedAttribute(icon))\" collapsed=\"\(collapsed ? "true" : "false")\">"
            ]
            if instanceTitle != title {
                output.append("\(indentation)  <instance-title>\(escapedText(instanceTitle))</instance-title>")
            }
            output.append(contentsOf: lines(for: block.children, depth: depth + 1))
            output.append("\(indentation)</element>")
            return output
        default:
            let body = block.inlines.map(\.plainText).joined()
            let text = (prefix(for: block, siblings: siblings, index: index) + body)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : ["\(indentation)\(text)"]
        }
    }

    private static func prefix(for block: RichBlock, siblings: [RichBlock], index: Int) -> String {
        switch block.kind {
        case .paragraph:
            return ""
        case .heading1:
            return "# "
        case .heading2:
            return "## "
        case .heading3:
            return "### "
        case .quote:
            return "> "
        case .bulletList:
            return "- "
        case .numberedList:
            return "\(numberedListPosition(in: siblings, before: index)). "
        case .checklist:
            return (block.checked ?? false) ? "[x] " : "[ ] "
        case .divider, .image, .element, .content, .research:
            return ""
        }
    }

    private static func numberedListPosition(in siblings: [RichBlock], before index: Int) -> Int {
        var position = 1
        var cursor = index - 1
        while cursor >= 0, siblings[cursor].kind == .numberedList {
            position += 1
            cursor -= 1
        }
        return position
    }

    private static func escapedAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum DocumentElementStoreError: Error, Equatable {
    case emptyTitle
    case definitionNotFound(UUID)
}

@MainActor
final class DocumentElementStore: ObservableObject {
    @Published private(set) var definitions: [DocumentElementDefinition] = []

    let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(
        fileURL: URL = DocumentElementStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    nonisolated static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("CosmoOS", isDirectory: true)
            .appendingPathComponent("Elements.json")
    }

    var activeDefinitions: [DocumentElementDefinition] {
        definitions
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    @discardableResult
    func createDefinition(title: String, systemIcon: String) throws -> DocumentElementDefinition {
        let now = Date()
        let definition = DocumentElementDefinition(
            title: normalizedTitle(title),
            systemIcon: normalizedIcon(systemIcon),
            createdAt: now,
            updatedAt: now
        )
        definitions.append(definition)
        try persist()
        return definition
    }

    @discardableResult
    func updateDefinition(id: UUID, title: String, systemIcon: String) throws -> DocumentElementDefinition {
        guard let index = definitions.firstIndex(where: { $0.id == id }) else {
            throw DocumentElementStoreError.definitionNotFound(id)
        }

        definitions[index].title = normalizedTitle(title)
        definitions[index].systemIcon = normalizedIcon(systemIcon)
        definitions[index].updatedAt = Date()
        try persist()
        return definitions[index]
    }

    func disableDefinition(id: UUID) throws {
        guard let index = definitions.firstIndex(where: { $0.id == id }) else {
            throw DocumentElementStoreError.definitionNotFound(id)
        }

        definitions[index].isEnabled = false
        definitions[index].updatedAt = Date()
        try persist()
    }

    func search(_ query: String) -> [DocumentElementDefinition] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return activeDefinitions }

        return activeDefinitions.filter { definition in
            definition.title.localizedCaseInsensitiveContains(normalizedQuery)
                || definition.systemIcon.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private func load() {
        do {
            try ensureParentDirectoryExists()
            guard fileManager.fileExists(atPath: fileURL.path) else {
                definitions = []
                try persist()
                return
            }

            let data = try Data(contentsOf: fileURL)
            definitions = try decoder.decode([DocumentElementDefinition].self, from: data)
                .map { definition in
                    var sanitized = definition
                    sanitized.systemIcon = DocumentElementSymbol.validName(definition.systemIcon)
                    return sanitized
                }
        } catch {
            recoverFromCorruptStore()
        }
    }

    private func recoverFromCorruptStore() {
        do {
            try ensureParentDirectoryExists()
            if fileManager.fileExists(atPath: fileURL.path) {
                let timestamp = ISO8601.string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                let recoveryURL = fileURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("Elements.corrupt-\(timestamp).json")
                try? fileManager.removeItem(at: recoveryURL)
                try fileManager.moveItem(at: fileURL, to: recoveryURL)
            }

            definitions = []
            try persist()
        } catch {
            definitions = []
        }
    }

    private func persist() throws {
        try ensureParentDirectoryExists()
        let data = try encoder.encode(definitions)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureParentDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Element" : trimmed
    }

    private func normalizedIcon(_ systemIcon: String) -> String {
        DocumentElementSymbol.validName(systemIcon)
    }
}
