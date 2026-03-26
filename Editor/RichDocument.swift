import AppKit
import Foundation
import SwiftUI

enum RichTextMark: String, Codable, CaseIterable, Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
}

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

    var headingLevelInt: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        default: return nil
        }
    }
}

public struct RichMention: Codable, Equatable, Hashable, Sendable {
    var entityUUID: String
    var entityID: Int64?
    var entityType: EntityType
    var titleSnapshot: String

    var displayText: String {
        "@\(titleSnapshot)"
    }
}

struct RichImageReference: Codable, Equatable, Hashable, Sendable {
    var path: String
    var width: CGFloat
    var height: CGFloat
}

struct RichInlineNode: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case text
        case mention
        case imageRef
    }

    var id: UUID = UUID()
    var kind: Kind
    var text: String?
    var marks: Set<RichTextMark> = []
    var mention: RichMention?
    var image: RichImageReference?

    static func text(_ text: String, marks: Set<RichTextMark> = []) -> RichInlineNode {
        RichInlineNode(kind: .text, text: text, marks: marks)
    }

    static func mention(_ mention: RichMention, marks: Set<RichTextMark> = []) -> RichInlineNode {
        RichInlineNode(kind: .mention, marks: marks, mention: mention)
    }

    static func image(_ image: RichImageReference) -> RichInlineNode {
        RichInlineNode(kind: .imageRef, image: image)
    }
}

struct RichBlock: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: RichBlockKind
    var inlines: [RichInlineNode] = []
    var checked: Bool? = nil

    static func paragraph(_ text: String) -> RichBlock {
        RichBlock(kind: .paragraph, inlines: [.text(text)])
    }
}

struct RichDocument: Codable, Equatable, Hashable, Sendable {
    var blocks: [RichBlock]

    static let empty = RichDocument(blocks: [])

    var isEmpty: Bool {
        blocks.allSatisfy { block in
            switch block.kind {
            case .divider:
                return false
            default:
                return block.inlines.allSatisfy { node in
                    switch node.kind {
                    case .text:
                        return (node.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    case .mention:
                        return false
                    case .imageRef:
                        return false
                    }
                }
            }
        }
    }

    var plainText: String {
        blocks.enumerated().map { index, block in
            let prefix: String
            switch block.kind {
            case .paragraph:
                prefix = ""
            case .heading1:
                prefix = "# "
            case .heading2:
                prefix = "## "
            case .heading3:
                prefix = "### "
            case .quote:
                prefix = "│ "
            case .divider:
                return "───────────────"
            case .bulletList:
                prefix = "• "
            case .numberedList:
                // Compute list-relative position (count consecutive .numberedList blocks before this one)
                var listPosition = 1
                var j = index - 1
                while j >= 0 && blocks[j].kind == .numberedList {
                    listPosition += 1
                    j -= 1
                }
                prefix = "\(listPosition). "
            case .checklist:
                prefix = (block.checked ?? false) ? "☑ " : "☐ "
            case .image:
                return "[Image]"
            }

            let body = block.inlines.map(\.plainText).joined()
            return prefix + body
        }
        .joined(separator: "\n")
    }

    static func migrateLegacy(_ text: String) -> RichDocument {
        guard !text.isEmpty else { return .empty }
        let lines = text.components(separatedBy: .newlines)
        let blocks = lines.map { RichDocument.block(fromLegacyLine: $0) }
        return RichDocument(blocks: collapseTrailingEmptyParagraphs(blocks))
    }

    private static func block(fromLegacyLine line: String) -> RichBlock {
        if line == "───────────────" || line.trimmingCharacters(in: .whitespaces) == "---" {
            return RichBlock(kind: .divider)
        }
        if line.hasPrefix("### ") {
            return RichBlock(kind: .heading3, inlines: [.text(String(line.dropFirst(4)))])
        }
        if line.hasPrefix("## ") {
            return RichBlock(kind: .heading2, inlines: [.text(String(line.dropFirst(3)))])
        }
        if line.hasPrefix("# ") {
            return RichBlock(kind: .heading1, inlines: [.text(String(line.dropFirst(2)))])
        }
        if line.hasPrefix("│ ") {
            return RichBlock(kind: .quote, inlines: [.text(String(line.dropFirst(2)))])
        }
        if line.hasPrefix("• ") {
            return RichBlock(kind: .bulletList, inlines: [.text(String(line.dropFirst(2)))])
        }
        if line.hasPrefix("☐ ") {
            return RichBlock(kind: .checklist, inlines: [.text(String(line.dropFirst(2)))], checked: false)
        }
        if line.hasPrefix("☑ ") {
            return RichBlock(kind: .checklist, inlines: [.text(String(line.dropFirst(2)))], checked: true)
        }
        if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            return RichBlock(kind: .numberedList, inlines: [.text(String(line[match.upperBound...]))])
        }
        return RichBlock(kind: .paragraph, inlines: [.text(line)])
    }

    private static func collapseTrailingEmptyParagraphs(_ blocks: [RichBlock]) -> [RichBlock] {
        var result = blocks
        while let last = result.last,
              last.kind == .paragraph,
              last.inlines.allSatisfy({ ($0.text ?? "").isEmpty }) {
            result.removeLast()
        }
        return result
    }
}

extension RichInlineNode {
    var plainText: String {
        switch kind {
        case .text:
            return text ?? ""
        case .mention:
            return mention?.displayText ?? ""
        case .imageRef:
            return "[Image]"
        }
    }
}

enum RichDocumentMetadataKeys {
    static let titleDocument = "richTitleDocument"
    static let bodyDocument = "richBodyDocument"
    static let contentDraftDocument = "richDraftDocument"
}

enum RichDocumentMetadataStorage {
    static func readDocument(from metadata: String?, key: String) -> RichDocument? {
        guard let metadata,
              let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[key],
              JSONSerialization.isValidJSONObject(value),
              let docData = try? JSONSerialization.data(withJSONObject: value) else {
            return nil
        }
        return try? JSONDecoder().decode(RichDocument.self, from: docData)
    }

    static func writeDocument(_ document: RichDocument?, into metadata: String?, key: String) -> String? {
        var dict: [String: Any] = [:]
        if let metadata,
           let data = metadata.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = decoded
        }

        if let document,
           let data = try? JSONEncoder().encode(document),
           let object = try? JSONSerialization.jsonObject(with: data) {
            dict[key] = object
        } else {
            dict[key] = nil
        }

        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return metadata
        }
        return string
    }
}

enum RichDocumentAttributeKeys {
    static let entityType = NSAttributedString.Key("CosmoEntityType")
    static let entityID = NSAttributedString.Key("CosmoEntityId")
    static let entityUUID = NSAttributedString.Key("CosmoEntityUUID")
    static let imagePath = NSAttributedString.Key("CosmoImagePath")
    static let headingLevel = NSAttributedString.Key("CosmoHeadingLevel")
}

enum RichDocumentSerializer {
    static func attributedString(
        from document: RichDocument,
        fontSize: CGFloat = 16,
        darkMode: Bool = false,
        singleLine: Bool = false,
        baseFontWeight: NSFont.Weight = .regular,
        titleMode: Bool = false
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let textColor = darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary)

        for (index, block) in document.blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes(
                    fontSize: fontSize,
                    darkMode: darkMode,
                    singleLine: singleLine,
                    baseFontWeight: baseFontWeight,
                    titleMode: titleMode
                )))
            }

            // Compute list-relative position for numbered lists
            var listPosition = 1
            if block.kind == .numberedList {
                var j = index - 1
                while j >= 0 && document.blocks[j].kind == .numberedList {
                    listPosition += 1
                    j -= 1
                }
            }
            let prefix = blockPrefix(for: block, listPosition: listPosition)
            if !prefix.isEmpty {
                result.append(NSAttributedString(string: prefix, attributes: blockPrefixAttributes(
                    for: block,
                    fontSize: fontSize,
                    darkMode: darkMode,
                    singleLine: singleLine,
                    baseFontWeight: baseFontWeight,
                    titleMode: titleMode
                )))
            }

            if block.kind == .divider {
                result.append(NSAttributedString(string: "───────────────", attributes: [
                    .font: NSFont.systemFont(ofSize: max(12, fontSize - 3)),
                    .foregroundColor: textColor.withAlphaComponent(0.45)
                ]))
                continue
            }

            if block.kind == .image, block.inlines.isEmpty {
                result.append(imageFallbackAttributedString(fontSize: fontSize, darkMode: darkMode))
                continue
            }

            for node in block.inlines {
                switch node.kind {
                case .text:
                    let string = node.text ?? ""
                    result.append(NSAttributedString(string: string, attributes: inlineAttributes(
                        marks: node.marks,
                        block: block,
                        fontSize: fontSize,
                        darkMode: darkMode,
                        singleLine: singleLine,
                        baseFontWeight: baseFontWeight,
                        titleMode: titleMode
                    )))
                case .mention:
                    guard let mention = node.mention else { continue }
                    var attrs = inlineAttributes(
                        marks: node.marks,
                        block: block,
                        fontSize: fontSize,
                        darkMode: darkMode,
                        singleLine: singleLine,
                        baseFontWeight: baseFontWeight,
                        titleMode: titleMode
                    )
                    let color = CosmoMentionColors.nsColor(for: mention.entityType)
                    attrs[.foregroundColor] = color
                    attrs[.backgroundColor] = color.withAlphaComponent(0.1)
                    attrs[RichDocumentAttributeKeys.entityType] = mention.entityType.rawValue
                    attrs[RichDocumentAttributeKeys.entityUUID] = mention.entityUUID
                    if let entityID = mention.entityID {
                        attrs[RichDocumentAttributeKeys.entityID] = entityID
                        attrs[.link] = "cosmo://\(mention.entityType.rawValue)/\(entityID)"
                    }
                    result.append(NSAttributedString(string: mention.displayText, attributes: attrs))
                case .imageRef:
                    guard let image = node.image else { continue }
                    if let attachment = imageAttachment(for: image) {
                        let attributed = NSMutableAttributedString(attachment: attachment)
                        attributed.addAttribute(RichDocumentAttributeKeys.imagePath, value: image.path, range: NSRange(location: 0, length: attributed.length))
                        result.append(attributed)
                    } else {
                        result.append(imageFallbackAttributedString(fontSize: fontSize, darkMode: darkMode))
                    }
                }
            }
        }

        if result.length == 0 {
            return NSAttributedString(string: "", attributes: baseAttributes(
                fontSize: fontSize,
                darkMode: darkMode,
                singleLine: singleLine,
                baseFontWeight: baseFontWeight,
                titleMode: titleMode
            ))
        }

        return result
    }

    static func document(from attributedString: NSAttributedString) -> RichDocument {
        guard attributedString.length > 0 else { return .empty }

        let string = attributedString.string as NSString
        var blocks: [RichBlock] = []
        var lineStart = 0

        while lineStart <= string.length {
            let lineRange = string.lineRange(for: NSRange(location: min(lineStart, max(0, string.length - 1)), length: 0))
            if lineRange.location + lineRange.length > attributedString.length {
                break
            }

            let rawLine = attributedString.attributedSubstring(from: lineRange)
            let trimmedLine = trimTrailingNewline(from: rawLine)
            blocks.append(block(from: trimmedLine))

            lineStart = lineRange.location + lineRange.length
            if lineStart >= string.length { break }
        }

        return RichDocument(blocks: blocks)
    }

    private static func trimTrailingNewline(from attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        while mutable.length > 0 {
            let lastRange = NSRange(location: mutable.length - 1, length: 1)
            let char = (mutable.string as NSString).substring(with: lastRange)
            if char == "\n" || char == "\r" {
                mutable.deleteCharacters(in: lastRange)
            } else {
                break
            }
        }
        return mutable
    }

    private static func block(from line: NSAttributedString) -> RichBlock {
        if line.length == 0 {
            return RichBlock(kind: .paragraph)
        }

        if lineContainsOnlyImage(line) {
            return RichBlock(kind: .image, inlines: inlineNodes(from: line))
        }

        let text = line.string
        if text == "───────────────" {
            return RichBlock(kind: .divider)
        }

        // Detect headings by custom attribute (preferred over text prefix)
        if line.length > 0,
           let level = line.attribute(RichDocumentAttributeKeys.headingLevel, at: 0, effectiveRange: nil) as? Int {
            let kind: RichBlockKind = level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3
            return RichBlock(kind: kind, inlines: inlineNodes(from: line))
        }

        // Fallback: detect by text prefix (backward compat for legacy documents)
        let (kind, contentStart, checked) = blockDescriptor(for: text)
        let contentRange = NSRange(location: min(contentStart, line.length), length: max(0, line.length - min(contentStart, line.length)))
        let content = line.attributedSubstring(from: contentRange)
        return RichBlock(kind: kind, inlines: inlineNodes(from: content), checked: checked)
    }

    private static func blockDescriptor(for text: String) -> (RichBlockKind, Int, Bool?) {
        if text.hasPrefix("### ") { return (.heading3, 4, nil) }
        if text.hasPrefix("## ") { return (.heading2, 3, nil) }
        if text.hasPrefix("# ") { return (.heading1, 2, nil) }
        if text.hasPrefix("│ ") { return (.quote, 2, nil) }
        if text.hasPrefix("• ") { return (.bulletList, 2, nil) }
        if text.hasPrefix("☐ ") { return (.checklist, 2, false) }
        if text.hasPrefix("☑ ") { return (.checklist, 2, true) }
        if let range = text.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            return (.numberedList, text.distance(from: text.startIndex, to: range.upperBound), nil)
        }
        return (.paragraph, 0, nil)
    }

    private static func inlineNodes(from attributedString: NSAttributedString) -> [RichInlineNode] {
        var nodes: [RichInlineNode] = []
        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { attributes, range, _ in
            if let attachment = attributes[.attachment] as? NSTextAttachment,
               let imageNode = imageNode(from: attachment, attributes: attributes) {
                nodes.append(.image(imageNode))
                return
            }

            if let entityTypeRaw = attributes[RichDocumentAttributeKeys.entityType] as? String,
               let entityType = EntityType(rawValue: entityTypeRaw),
               let entityUUID = attributes[RichDocumentAttributeKeys.entityUUID] as? String {
                let entityID: Int64?
                if let value = attributes[RichDocumentAttributeKeys.entityID] as? Int64 {
                    entityID = value
                } else if let value = attributes[RichDocumentAttributeKeys.entityID] as? NSNumber {
                    entityID = value.int64Value
                } else {
                    entityID = nil
                }
                let title = (attributedString.string as NSString).substring(with: range).replacingOccurrences(of: "@", with: "")
                nodes.append(.mention(RichMention(
                    entityUUID: entityUUID,
                    entityID: entityID,
                    entityType: entityType,
                    titleSnapshot: title
                ), marks: marks(from: attributes)))
                return
            }

            let text = (attributedString.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }
            let marks = marks(from: attributes)
            if case let .some(last) = nodes.last,
               last.kind == .text,
               last.marks == marks {
                var merged = last
                merged.text = (last.text ?? "") + text
                nodes[nodes.count - 1] = merged
            } else {
                nodes.append(.text(text, marks: marks))
            }
        }
        return nodes
    }

    private static func lineContainsOnlyImage(_ line: NSAttributedString) -> Bool {
        guard line.length > 0 else { return false }
        var containsAttachment = false
        var containsNonWhitespaceText = false
        line.enumerateAttributes(in: NSRange(location: 0, length: line.length), options: []) { attributes, range, _ in
            if attributes[.attachment] is NSTextAttachment {
                containsAttachment = true
                return
            }
            let text = (line.string as NSString).substring(with: range)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                containsNonWhitespaceText = true
            }
        }
        return containsAttachment && !containsNonWhitespaceText
    }

    private static func marks(from attributes: [NSAttributedString.Key: Any]) -> Set<RichTextMark> {
        var marks: Set<RichTextMark> = []
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) {
                marks.insert(.bold)
            }
            if traits.contains(.italic) {
                marks.insert(.italic)
            }
        }
        if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
            marks.insert(.underline)
        }
        if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 {
            marks.insert(.strikethrough)
        }
        return marks
    }

    private static func imageNode(from attachment: NSTextAttachment, attributes: [NSAttributedString.Key: Any]) -> RichImageReference? {
        if let existingPath = attributes[RichDocumentAttributeKeys.imagePath] as? String,
           let image = ImageStore.load(path: existingPath) {
            let size = image.size
            return RichImageReference(path: existingPath, width: size.width, height: size.height)
        }

        let data = attachment.fileWrapper?.regularFileContents ?? attachment.image?.pngData() ?? attachment.image?.tiffRepresentation
        guard let data else {
            return nil
        }

        let filename = attachment.fileWrapper?.preferredFilename
        guard let saved = try? ImageStore.save(data, originalFilename: filename) else {
            return nil
        }

        return RichImageReference(path: saved.path, width: saved.width, height: saved.height)
    }

    private static func imageAttachment(for image: RichImageReference) -> NSTextAttachment? {
        guard let nsImage = ImageStore.load(path: image.path) else {
            return nil
        }

        let attachment = NSTextAttachment()
        attachment.image = nsImage.scaled(toFit: CGSize(width: min(680, image.width), height: 420))
        return attachment
    }

    private static func imageFallbackAttributedString(fontSize: CGFloat, darkMode: Bool) -> NSAttributedString {
        let color = darkMode ? NSColor.white.withAlphaComponent(0.65) : NSColor(CosmoColors.textSecondary)
        return NSAttributedString(string: "[Image]", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color
        ])
    }

    private static func blockPrefix(for block: RichBlock, listPosition: Int) -> String {
        switch block.kind {
        case .paragraph, .image:
            return ""
        case .heading1, .heading2, .heading3:
            return ""  // Headings use attribute-based detection, no visible prefix
        case .quote:
            return "│ "
        case .divider:
            return ""
        case .bulletList:
            return "• "
        case .numberedList:
            return "\(listPosition). "
        case .checklist:
            return (block.checked ?? false) ? "☑ " : "☐ "
        }
    }

    private static func blockPrefixAttributes(
        for block: RichBlock,
        fontSize: CGFloat,
        darkMode: Bool,
        singleLine: Bool,
        baseFontWeight: NSFont.Weight,
        titleMode: Bool
    ) -> [NSAttributedString.Key: Any] {
        let color = darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary)
        switch block.kind {
        case .quote:
            return [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .light),
                .foregroundColor: color.withAlphaComponent(0.7)
            ]
        default:
            return baseAttributes(
                fontSize: fontSize,
                darkMode: darkMode,
                singleLine: singleLine,
                baseFontWeight: baseFontWeight,
                titleMode: titleMode
            )
        }
    }

    private static func baseAttributes(
        fontSize: CGFloat,
        darkMode: Bool,
        singleLine: Bool,
        baseFontWeight: NSFont.Weight,
        titleMode: Bool
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        if singleLine || titleMode {
            paragraphStyle.lineSpacing = 0
            paragraphStyle.paragraphSpacing = 0
        } else {
            paragraphStyle.lineSpacing = 6
            paragraphStyle.paragraphSpacing = 12
        }
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight),
            .foregroundColor: darkMode ? NSColor.white : NSColor(CosmoColors.textPrimary),
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func inlineAttributes(
        marks: Set<RichTextMark>,
        block: RichBlock,
        fontSize: CGFloat,
        darkMode: Bool,
        singleLine: Bool,
        baseFontWeight: NSFont.Weight,
        titleMode: Bool
    ) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes(
            fontSize: fontSize,
            darkMode: darkMode,
            singleLine: singleLine,
            baseFontWeight: baseFontWeight,
            titleMode: titleMode
        )
        var font = blockFont(
            for: block,
            fontSize: fontSize,
            baseFontWeight: baseFontWeight,
            titleMode: titleMode
        )

        if marks.contains(.bold) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if marks.contains(.italic) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        attributes[.font] = font

        if marks.contains(.underline) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if marks.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        if block.kind == .quote {
            attributes[.foregroundColor] = (attributes[.foregroundColor] as? NSColor)?.withAlphaComponent(0.9)
        }

        // Headings: embed level attribute + paragraph spacing for round-trip detection
        if let headingLevel = block.kind.headingLevelInt, !titleMode {
            attributes[RichDocumentAttributeKeys.headingLevel] = headingLevel
            let headingParagraph = NSMutableParagraphStyle()
            headingParagraph.lineSpacing = 4
            headingParagraph.paragraphSpacing = 12
            // Proportional top margin — larger headings get more breathing room
            switch headingLevel {
            case 1: headingParagraph.paragraphSpacingBefore = 32
            case 2: headingParagraph.paragraphSpacingBefore = 24
            default: headingParagraph.paragraphSpacingBefore = 16
            }
            attributes[.paragraphStyle] = headingParagraph
        }

        return attributes
    }

    private static func blockFont(
        for block: RichBlock,
        fontSize: CGFloat,
        baseFontWeight: NSFont.Weight,
        titleMode: Bool
    ) -> NSFont {
        guard !titleMode else {
            return NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
        }
        switch block.kind {
        case .heading1:
            return NSFont.systemFont(ofSize: max(32, fontSize + 16), weight: .bold)
        case .heading2:
            return NSFont.systemFont(ofSize: max(24, fontSize + 8), weight: .semibold)
        case .heading3:
            return NSFont.systemFont(ofSize: max(20, fontSize + 4), weight: .medium)
        default:
            return NSFont.systemFont(ofSize: fontSize, weight: baseFontWeight)
        }
    }
}

private extension NSTextAttachment {
    var image: NSImage? {
        get {
            (attachmentCell as? NSTextAttachmentCell)?.image
        }
        set {
            if let newValue {
                attachmentCell = NSTextAttachmentCell(imageCell: newValue)
            } else {
                attachmentCell = nil
            }
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
