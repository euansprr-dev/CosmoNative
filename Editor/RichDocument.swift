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
    case element
    case content
    case research
    case callout
    case toggle
    case code
    case sketch

    var headingLevelInt: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
            default: return nil
        }
    }

    var isTextEditableBlock: Bool {
        switch self {
        case .paragraph, .heading1, .heading2, .heading3, .quote, .bulletList, .numberedList, .checklist, .content, .research,
             .callout, .toggle, .code:
            return true
        case .divider, .image, .element, .sketch:
            return false
        }
    }

    var splitContinuationKind: RichBlockKind {
        switch self {
        case .heading1, .heading2, .heading3, .quote, .content, .research, .callout:
            return .paragraph
        case .bulletList:
            return .bulletList
        case .numberedList:
            return .numberedList
        case .checklist:
            return .checklist
        case .paragraph:
            return .paragraph
        case .code:
            // Return inside a code block inserts a soft break; a structural
            // split (hard-newline backstop) keeps the continuation as code.
            return .code
        case .divider, .image, .element, .toggle, .sketch:
            return .paragraph
        }
    }
}

// MARK: - Sketch

/// One drawn point — deliberately explicit (not CGPoint) so the payload is
/// hashable and byte-portable to iOS later.
struct RichSketchPoint: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
}

struct RichSketchStroke: Codable, Equatable, Hashable, Sendable {
    var points: [RichSketchPoint]
    var width: Double
    /// NoteInkPalette tone id, or "ink" for the document text color.
    var inkID: String
    var isHighlighter: Bool

    init(points: [RichSketchPoint] = [], width: Double = 2.5, inkID: String = "ink", isHighlighter: Bool = false) {
        self.points = points
        self.width = width
        self.inkID = inkID
        self.isHighlighter = isHighlighter
    }

    private enum CodingKeys: String, CodingKey {
        case points, width, inkID, isHighlighter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = (try? container.decodeIfPresent([RichSketchPoint].self, forKey: .points)) ?? []
        width = (try? container.decodeIfPresent(Double.self, forKey: .width)) ?? 2.5
        inkID = (try? container.decodeIfPresent(String.self, forKey: .inkID)) ?? "ink"
        isHighlighter = (try? container.decodeIfPresent(Bool.self, forKey: .isHighlighter)) ?? false
    }
}

/// A freehand drawing board inside a note. Strokes are plain JSON — no
/// PencilKit archives — so any platform can render and edit them.
struct RichSketchDrawing: Codable, Equatable, Hashable, Sendable {
    var strokes: [RichSketchStroke]
    var height: Double

    static let defaultHeight: Double = 240
    static let minHeight: Double = 120
    static let maxHeight: Double = 600

    init(strokes: [RichSketchStroke] = [], height: Double = RichSketchDrawing.defaultHeight) {
        self.strokes = strokes
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case strokes, height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strokes = (try? container.decodeIfPresent([RichSketchStroke].self, forKey: .strokes)) ?? []
        height = (try? container.decodeIfPresent(Double.self, forKey: .height)) ?? Self.defaultHeight
    }
}

/// The tinted-block style carried by a callout: an SF Symbol and a
/// `NoteInkPalette` tone ID. Lenient-decoded so future fields never break
/// older documents.
struct RichCalloutStyle: Codable, Equatable, Hashable, Sendable {
    var icon: String
    var toneID: String

    static let `default` = RichCalloutStyle(icon: "sparkles", toneID: NoteInkPalette.defaultToneID)

    init(icon: String, toneID: String) {
        self.icon = icon
        self.toneID = toneID
    }

    private enum CodingKeys: String, CodingKey {
        case icon, toneID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        icon = (try? container.decodeIfPresent(String.self, forKey: .icon)) ?? Self.default.icon
        toneID = (try? container.decodeIfPresent(String.self, forKey: .toneID)) ?? Self.default.toneID
    }
}

struct RichHeadingMetadata: Codable, Equatable, Hashable, Sendable {
    var isCollapsed: Bool
    var collapsedBlocks: [RichBlock]
    /// Whether the heading offers the disclosure affordance at all. Plain
    /// headings (the default) are purely visual — no chevron, no gutter.
    /// Collapsible headings are created explicitly ("Toggle Heading" in the
    /// slash menu), mirroring Notion's heading vs. toggle-heading split.
    var isCollapsible: Bool

    init(isCollapsed: Bool = false, collapsedBlocks: [RichBlock] = [], isCollapsible: Bool = false) {
        self.isCollapsed = isCollapsed
        self.collapsedBlocks = collapsedBlocks
        self.isCollapsible = isCollapsible
    }

    private enum CodingKeys: String, CodingKey {
        case isCollapsed
        case collapsedBlocks
        case isCollapsible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        collapsedBlocks = try container.decodeIfPresent([RichBlock].self, forKey: .collapsedBlocks) ?? []
        // Documents written before the plain/toggle split have no key: only
        // headings actually holding a folded section keep the affordance —
        // their hidden blocks must stay reachable. Everything else becomes a
        // plain heading.
        isCollapsible = try container.decodeIfPresent(Bool.self, forKey: .isCollapsible)
            ?? (isCollapsed || !collapsedBlocks.isEmpty)
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
    /// Intrinsic pixel dimensions of the source image.
    var width: CGFloat
    var height: CGFloat
    /// User-chosen on-screen width in points. `nil` ⇒ default size (back-compat: older
    /// documents have no stored size and fall back to `ImageResizeMath.defaultDisplayWidth`).
    var displayWidth: CGFloat?
    /// Supabase Storage URL in the shared `capture-media` bucket. Populated when
    /// a note image mirrors to the cloud so it renders on every device; `path`
    /// stays the device-local file. Decodes nil from older documents; ignored by
    /// older builds that don't know the key — safe both directions.
    var remoteURL: String? = nil
}

/// Pure geometry for proportional (aspect-locked) image resizing. Shared by the SwiftUI
/// (Note focus mode) and AppKit (Content focus mode) resize surfaces, and unit-tested in
/// isolation. Height always follows from width and the intrinsic aspect ratio, so images
/// can never be distorted.
enum ImageResizeMath {
    /// Smallest on-screen width the user can shrink an image to, in points.
    static let minWidth: CGFloat = 64

    /// Aspect ratio (w/h) of the source image, guarded against zero/NaN.
    static func aspectRatio(intrinsic: CGSize) -> CGFloat {
        guard intrinsic.width > 0, intrinsic.height > 0 else { return 1 }
        return intrinsic.width / intrinsic.height
    }

    /// The width an image renders at when the user hasn't picked one. Reproduces the
    /// historical default of fitting within `min(680, w) × 420` so existing documents keep
    /// their previous appearance.
    static func defaultDisplayWidth(intrinsic: CGSize) -> CGFloat {
        let w = max(1, intrinsic.width)
        let h = max(1, intrinsic.height)
        let ratio = min(min(680, w) / w, 420 / h, 1)
        return w * ratio
    }

    /// Final on-screen size: chosen-or-default width, clamped to `[minWidth, maxWidth]`,
    /// with height derived from the aspect ratio.
    static func resolvedSize(displayWidth: CGFloat?, intrinsic: CGSize, maxWidth: CGFloat) -> CGSize {
        let aspect = aspectRatio(intrinsic: intrinsic)
        let base = displayWidth ?? defaultDisplayWidth(intrinsic: intrinsic)
        let upper = max(minWidth, maxWidth)
        let width = min(max(base, minWidth), upper)
        return CGSize(width: width, height: (width / aspect).rounded())
    }

    /// New aspect-locked width while dragging a corner. `startWidth` is the width when the
    /// drag began; `deltaX` is the dragged corner's horizontal translation; `growsRight` is
    /// true for right-edge corners (drag right → grow) and false for left-edge corners
    /// (drag left → grow). Result is clamped to `[minWidth, maxWidth]`.
    static func cornerResizedWidth(startWidth: CGFloat, deltaX: CGFloat, growsRight: Bool, maxWidth: CGFloat) -> CGFloat {
        let signed = growsRight ? deltaX : -deltaX
        let upper = max(minWidth, maxWidth)
        return min(max(startWidth + signed, minWidth), upper)
    }

    /// "648 × 432" for the live size badge.
    static func format(size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }
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
    var element: RichElementInstance? = nil
    var heading: RichHeadingMetadata? = nil
    var children: [RichBlock] = []
    /// Callout chrome (icon + tone). Only meaningful when `kind == .callout`.
    var callout: RichCalloutStyle? = nil
    /// Toggle disclosure state. Only meaningful when `kind == .toggle`.
    var toggleCollapsed: Bool? = nil
    /// Freehand drawing payload. Only meaningful when `kind == .sketch`.
    var sketch: RichSketchDrawing? = nil
    /// Forward-compat: a kind raw value this build doesn't know. The block
    /// renders/edits as a paragraph, but the original kind is preserved on
    /// re-encode so newer builds get their block back intact.
    var rawKind: String? = nil

    init(
        id: UUID = UUID(),
        kind: RichBlockKind,
        inlines: [RichInlineNode] = [],
        checked: Bool? = nil,
        element: RichElementInstance? = nil,
        heading: RichHeadingMetadata? = nil,
        children: [RichBlock] = [],
        callout: RichCalloutStyle? = nil,
        toggleCollapsed: Bool? = nil,
        sketch: RichSketchDrawing? = nil
    ) {
        self.id = id
        self.kind = kind
        self.inlines = inlines
        self.checked = checked
        self.element = element
        self.heading = kind.headingLevelInt == nil ? nil : (heading ?? RichHeadingMetadata())
        self.children = children
        self.callout = kind == .callout ? (callout ?? .default) : callout
        self.toggleCollapsed = kind == .toggle ? (toggleCollapsed ?? false) : toggleCollapsed
        self.sketch = kind == .sketch ? (sketch ?? RichSketchDrawing()) : sketch
    }

    static func paragraph(_ text: String) -> RichBlock {
        RichBlock(kind: .paragraph, inlines: [.text(text)])
    }

    static func element(
        _ definition: DocumentElementDefinition,
        children: [RichBlock] = [],
        isCollapsed: Bool = false,
        instanceTitle: String? = nil
    ) -> RichBlock {
        // A fresh instance is stamped with the definition's template
        // structure (regenerated IDs — instances own their copies).
        let seededChildren = children.isEmpty
            ? definition.templateChildren.map { $0.withRegeneratedIDs() }
            : children
        return RichBlock.element(
            RichElementInstance(
                definitionID: definition.id,
                titleSnapshot: definition.title,
                systemIconSnapshot: definition.systemIcon,
                isCollapsed: isCollapsed,
                instanceTitleSnapshot: instanceTitle ?? definition.title,
                tintSnapshot: definition.tintID
            ),
            children: seededChildren
        )
    }

    static func element(_ instance: RichElementInstance, children: [RichBlock] = []) -> RichBlock {
        RichBlock(kind: .element, element: instance, children: children)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case inlines
        case checked
        case element
        case heading
        case children
        case callout
        case toggleCollapsed
        case sketch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // Lenient kind decoding: an unknown raw value (written by a newer
        // build) degrades to a paragraph instead of throwing — a throw here
        // used to discard the entire document body. The original raw value is
        // kept so re-encoding round-trips the newer block untouched.
        let rawKindValue = try container.decode(String.self, forKey: .kind)
        if let knownKind = RichBlockKind(rawValue: rawKindValue) {
            kind = knownKind
            rawKind = nil
        } else {
            kind = .paragraph
            rawKind = rawKindValue
        }
        inlines = try container.decodeIfPresent([RichInlineNode].self, forKey: .inlines) ?? []
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked)
        element = try container.decodeIfPresent(RichElementInstance.self, forKey: .element)
        heading = try container.decodeIfPresent(RichHeadingMetadata.self, forKey: .heading)
        if kind.headingLevelInt != nil, heading == nil {
            heading = RichHeadingMetadata()
        }
        children = try container.decodeIfPresent([RichBlock].self, forKey: .children) ?? []
        callout = try? container.decodeIfPresent(RichCalloutStyle.self, forKey: .callout)
        if kind == .callout, callout == nil {
            callout = .default
        }
        toggleCollapsed = try? container.decodeIfPresent(Bool.self, forKey: .toggleCollapsed)
        if kind == .toggle, toggleCollapsed == nil {
            toggleCollapsed = false
        }
        sketch = try? container.decodeIfPresent(RichSketchDrawing.self, forKey: .sketch)
        if kind == .sketch, sketch == nil {
            sketch = RichSketchDrawing()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rawKind ?? kind.rawValue, forKey: .kind)
        try container.encode(inlines, forKey: .inlines)
        try container.encodeIfPresent(checked, forKey: .checked)
        try container.encodeIfPresent(element, forKey: .element)
        if kind.headingLevelInt != nil {
            try container.encode(heading ?? RichHeadingMetadata(), forKey: .heading)
        }
        if !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
        try container.encodeIfPresent(callout, forKey: .callout)
        try container.encodeIfPresent(toggleCollapsed, forKey: .toggleCollapsed)
        try container.encodeIfPresent(sketch, forKey: .sketch)
    }
}

extension RichBlock {
    var plainInlineText: String {
        inlines.map(\.plainText).joined()
    }
}

struct RichDocument: Codable, Equatable, Hashable, Sendable {
    var blocks: [RichBlock]

    static let empty = RichDocument(blocks: [])

    var isEmpty: Bool {
        blocks.allSatisfy { block in
            switch block.kind {
            case .divider, .image, .element, .sketch:
                return false
            case .toggle where !block.children.isEmpty:
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
        Self.plainText(for: blocks, depth: 0)
    }

    var containsCollapsedHiddenContent: Bool {
        Self.containsCollapsedHiddenContent(in: blocks)
    }

    /// True when any block (at any depth, including collapsed-away content)
    /// carries a visual or structured body — a sketch canvas, an image, an
    /// element container — that a plain-text rendering cannot represent.
    /// Surfaces that show notes as flattened text (the canvas thought card)
    /// must check this and fall back to real block rendering.
    var containsVisualBlocks: Bool {
        Self.containsVisualBlocks(in: blocks)
    }

    private static func containsVisualBlocks(in blocks: [RichBlock]) -> Bool {
        for block in blocks {
            switch block.kind {
            case .sketch, .image, .element:
                return true
            default:
                break
            }
            if block.inlines.contains(where: { $0.kind == .imageRef }) {
                return true
            }
            if containsVisualBlocks(in: block.children) {
                return true
            }
            if let collapsed = block.heading?.collapsedBlocks,
               containsVisualBlocks(in: collapsed) {
                return true
            }
        }
        return false
    }

    private static func plainText(for blocks: [RichBlock], depth: Int) -> String {
        let indentation = String(repeating: "  ", count: depth)
        // List-relative numbering as a running counter — this runs per
        // keystroke on the whole document, and the old backward scan made a
        // long numbered list quadratic in its length.
        var numberedRun = 0
        var entries: [String] = []
        entries.reserveCapacity(blocks.count)
        for block in blocks {
            numberedRun = block.kind == .numberedList ? numberedRun + 1 : 0
            entries.append(plainTextEntry(
                for: block,
                indentation: indentation,
                depth: depth,
                numberedPosition: numberedRun
            ))
        }
        return entries.joined(separator: "\n")
    }

    private static func plainTextEntry(
        for block: RichBlock,
        indentation: String,
        depth: Int,
        numberedPosition: Int
    ) -> String {
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
                return indentation + "───────────────"
            case .bulletList:
                prefix = "• "
            case .numberedList:
                prefix = "\(numberedPosition). "
            case .checklist:
                prefix = (block.checked ?? false) ? "☑ " : "☐ "
            case .content:
                prefix = ""
            case .research:
                prefix = ""
            case .callout:
                prefix = ""
            case .code:
                prefix = ""
            case .image:
                return indentation + "[Image]"
            case .sketch:
                return indentation + "[Sketch]"
            case .toggle:
                let header = block.inlines.map(\.plainText).joined()
                let childText = plainText(for: block.children, depth: depth + 1)
                let headerLine = indentation + "▸ " + header
                return childText.isEmpty ? headerLine : headerLine + "\n" + childText
            case .element:
                let title = block.element?.instanceTitleSnapshot ?? block.element?.titleSnapshot ?? "Untitled Element"
                let childText = plainText(for: block.children, depth: depth + 1)
                if childText.isEmpty {
                    return indentation + title
                }
                return indentation + title + "\n" + childText
            }

            let body = block.inlines.map(\.plainText).joined()
            let line = indentation + prefix + body
            if let collapsedBlocks = block.heading?.collapsedBlocks, !collapsedBlocks.isEmpty {
                let childText = plainText(for: collapsedBlocks, depth: depth)
                return childText.isEmpty ? line : line + "\n" + childText
            }
            return line
    }

    private static func containsCollapsedHiddenContent(in blocks: [RichBlock]) -> Bool {
        for block in blocks {
            if block.heading?.isCollapsed == true,
               !(block.heading?.collapsedBlocks.isEmpty ?? true) {
                return true
            }
            if block.element?.isCollapsed == true, !block.children.isEmpty {
                return true
            }
            if block.kind == .toggle, block.toggleCollapsed == true, !block.children.isEmpty {
                return true
            }
            if containsCollapsedHiddenContent(in: block.children) {
                return true
            }
            if let collapsedBlocks = block.heading?.collapsedBlocks,
               containsCollapsedHiddenContent(in: collapsedBlocks) {
                return true
            }
        }
        return false
    }

    static func migrateLegacy(_ text: String) -> RichDocument {
        guard !text.isEmpty else { return .empty }
        let lines = text.components(separatedBy: .newlines)
        let blocks = lines.map { RichDocument.block(fromLegacyLine: $0) }
        return RichDocument(blocks: collapseTrailingEmptyParagraphs(blocks))
    }

    static func block(fromLegacyLine line: String) -> RichBlock {
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

/// Process-wide memoization for RichDocument decodes. Reading a document out
/// of atom metadata costs a full JSON parse of the metadata column, a
/// re-serialization of the embedded object, and a Codable decode — and it runs
/// on the main thread at every block/editor mount (a thinkspace switch mounts
/// every visible note in one frame). Results are keyed by the exact source
/// string + metadata key, so any content change re-decodes.
final class RichDocumentDecodeCache: @unchecked Sendable {
    static let shared = RichDocumentDecodeCache()

    /// Preferred identity (mirrors Atom.DecodedColumnCache): a cheap
    /// (uuid, metadataKey) probe with the source string stored IN the entry
    /// and validated on every hit — hashing the whole multi-hundred-KB
    /// metadata string per probe was itself a per-mount tax. Any source
    /// mismatch re-decodes and replaces.
    private struct UUIDKey: Hashable {
        let uuid: String
        let metadataKey: String
    }

    private struct Entry {
        let source: String
        /// nil documents are cached too — "this metadata has no document
        /// under this key" is a stable fact of the source string.
        let document: RichDocument?
    }

    /// Fallback identity for call sites with no uuid: the exact source
    /// string, as before.
    private struct SourceKey: Hashable {
        let source: String
        let metadataKey: String
    }

    private var entriesByUUID: [UUIDKey: Entry] = [:]
    private var entriesBySource: [SourceKey: RichDocument?] = [:]
    private let lock = NSLock()
    private let limit = 512

    private init() {}

    func document(source: String, metadataKey: String, atomUUID: String? = nil, decode: () -> RichDocument?) -> RichDocument? {
        if let atomUUID, !atomUUID.isEmpty {
            let key = UUIDKey(uuid: atomUUID, metadataKey: metadataKey)
            lock.lock()
            let cached = entriesByUUID[key]
            lock.unlock()
            if let cached, cached.source == source { return cached.document }

            let decoded = decode()
            lock.lock()
            if entriesByUUID.count >= limit { entriesByUUID.removeAll(keepingCapacity: true) }
            entriesByUUID[key] = Entry(source: source, document: decoded)
            lock.unlock()
            return decoded
        }

        let key = SourceKey(source: source, metadataKey: metadataKey)
        lock.lock()
        let cached = entriesBySource[key]
        lock.unlock()
        if let cached { return cached }

        let decoded = decode()
        lock.lock()
        if entriesBySource.count >= limit { entriesBySource.removeAll(keepingCapacity: true) }
        entriesBySource[key] = decoded
        lock.unlock()
        return decoded
    }
}

enum RichDocumentMetadataStorage {
    /// `atomUUID`, when known, gives the decode cache a cheap stable identity
    /// (probe by uuid, validate by stored source) instead of hashing the
    /// whole metadata string per read.
    static func readDocument(from metadata: String?, key: String, atomUUID: String? = nil) -> RichDocument? {
        guard let metadata else { return nil }
        return RichDocumentDecodeCache.shared.document(source: metadata, metadataKey: key, atomUUID: atomUUID) {
            guard let data = metadata.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = dict[key],
                  JSONSerialization.isValidJSONObject(value),
                  let docData = try? JSONSerialization.data(withJSONObject: value) else {
                return nil
            }
            return try? JSONDecoder().decode(RichDocument.self, from: docData)
        }
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
    static let imageDisplayWidth = NSAttributedString.Key("CosmoImageDisplayWidth")
    static let headingLevel = NSAttributedString.Key("CosmoHeadingLevel")
    static let headingBlockID = NSAttributedString.Key("CosmoHeadingBlockID")
    static let headingCollapsed = NSAttributedString.Key("CosmoHeadingCollapsed")
    static let headingCollapsible = NSAttributedString.Key("CosmoHeadingCollapsible")
    static let headingCollapsedChildrenJSON = NSAttributedString.Key("CosmoHeadingCollapsedChildrenJSON")
    static let elementDepth = NSAttributedString.Key("CosmoElementDepth")
    static let elementInstanceID = NSAttributedString.Key("CosmoElementInstanceID")
    static let elementDefinitionID = NSAttributedString.Key("CosmoElementDefinitionID")
    static let elementTitle = NSAttributedString.Key("CosmoElementTitle")
    static let elementInstanceTitle = NSAttributedString.Key("CosmoElementInstanceTitle")
    static let elementIcon = NSAttributedString.Key("CosmoElementIcon")
    static let elementCollapsed = NSAttributedString.Key("CosmoElementCollapsed")
    static let elementChildrenJSON = NSAttributedString.Key("CosmoElementChildrenJSON")
}

enum RichDocumentSerializer {
    static func attributedString(
        from document: RichDocument,
        fontSize: CGFloat = 16,
        darkMode: Bool = false,
        singleLine: Bool = false,
        baseFontWeight: NSFont.Weight = .regular,
        titleMode: Bool = false,
        numberedListSeed: Int = 0
    ) -> NSAttributedString {
        attributedString(
            from: document,
            depth: 0,
            fontSize: fontSize,
            darkMode: darkMode,
            singleLine: singleLine,
            baseFontWeight: baseFontWeight,
            titleMode: titleMode,
            numberedListSeed: numberedListSeed
        )
    }

    private static func attributedString(
        from document: RichDocument,
        depth: Int,
        fontSize: CGFloat,
        darkMode: Bool,
        singleLine: Bool,
        baseFontWeight: NSFont.Weight,
        titleMode: Bool,
        numberedListSeed: Int = 0
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let textColor = darkMode ? NSColor.white : NSColor(DS.documentText)

        for (index, block) in document.blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: attributesWithDepth(
                    baseAttributes(
                        fontSize: fontSize,
                        darkMode: darkMode,
                        singleLine: singleLine,
                        baseFontWeight: baseFontWeight,
                        titleMode: titleMode
                    ),
                    depth: depth
                )))
            }

            let blockStart = result.length

            // Compute list-relative position for numbered lists. When the
            // run reaches the document's first block, the seed carries the
            // count of numbered blocks BEFORE this document — a block row
            // serializes a single-block document and can't see its siblings
            // (every item rendered "1." without it).
            var listPosition = 1
            if block.kind == .numberedList {
                var j = index - 1
                while j >= 0 && document.blocks[j].kind == .numberedList {
                    listPosition += 1
                    j -= 1
                }
                if j < 0 {
                    listPosition += numberedListSeed
                }
            }
            let prefix = blockPrefix(for: block, listPosition: listPosition)
            if !prefix.isEmpty {
                let prefixString = NSMutableAttributedString(string: prefix, attributes: blockPrefixAttributes(
                    for: block,
                    fontSize: fontSize,
                    darkMode: darkMode,
                    singleLine: singleLine,
                    baseFontWeight: baseFontWeight,
                    titleMode: titleMode
                ))
                // The stored ☐/☑ stays for round-trip + hit-testing but never
                // inks — CosmoTextView paints the circle checkbox over it.
                if block.kind == .checklist, prefixString.length >= 1 {
                    prefixString.addAttribute(
                        .foregroundColor,
                        value: NSColor.clear,
                        range: NSRange(location: 0, length: 1)
                    )
                }
                result.append(prefixString)
            }

            if block.kind == .divider {
                result.append(NSAttributedString(string: "───────────────", attributes: [
                    .font: NSFont.systemFont(ofSize: max(12, fontSize - 3)),
                    .foregroundColor: textColor.withAlphaComponent(0.45)
                ]))
                addDepth(depth, to: result, from: blockStart)
                continue
            }

            if block.kind == .image, block.inlines.isEmpty {
                result.append(imageFallbackAttributedString(fontSize: fontSize, darkMode: darkMode))
                addDepth(depth, to: result, from: blockStart)
                continue
            }

            if block.kind == .element {
                result.append(elementHeaderAttributedString(for: block, depth: depth, fontSize: fontSize, darkMode: darkMode))
                if !(block.element?.isCollapsed ?? false), !block.children.isEmpty {
                    let childIndentStart = result.length
                    result.append(NSAttributedString(string: "\n", attributes: attributesWithDepth(
                        baseAttributes(
                            fontSize: fontSize,
                            darkMode: darkMode,
                            singleLine: singleLine,
                            baseFontWeight: baseFontWeight,
                            titleMode: titleMode
                        ),
                        depth: depth + 1
                    )))
                    result.append(attributedString(
                        from: RichDocument(blocks: block.children),
                        depth: depth + 1,
                        fontSize: fontSize,
                        darkMode: darkMode,
                        singleLine: singleLine,
                        baseFontWeight: baseFontWeight,
                        titleMode: titleMode
                    ))
                    applyChildIndent(
                        to: result,
                        from: childIndentStart,
                        depth: depth + 1,
                        fontSize: fontSize
                    )
                }
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
                        let imageRange = NSRange(location: 0, length: attributed.length)
                        var imageAttrs: [NSAttributedString.Key: Any] = [RichDocumentAttributeKeys.imagePath: image.path]
                        if let displayWidth = image.displayWidth {
                            imageAttrs[RichDocumentAttributeKeys.imageDisplayWidth] = NSNumber(value: Double(displayWidth))
                        }
                        attributed.addAttributes(imageAttrs, range: imageRange)
                        result.append(attributed)
                    } else {
                        result.append(imageFallbackAttributedString(fontSize: fontSize, darkMode: darkMode))
                    }
                }
            }
            addDepth(depth, to: result, from: blockStart)
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
        var lines: [ParsedAttributedLine] = []
        var lineStart = 0

        // Blocks are delimited by hard newlines only (\n, \r, \r\n). U+2028
        // line separators are soft breaks within a block (Shift+Return) and
        // must survive the round trip as inline content.
        while lineStart < string.length {
            var lineEnd = lineStart
            while lineEnd < string.length {
                let character = string.character(at: lineEnd)
                if character == 0x0A || character == 0x0D { break }
                lineEnd += 1
            }

            let rawLine = attributedString.attributedSubstring(
                from: NSRange(location: lineStart, length: lineEnd - lineStart)
            )
            lines.append(parsedLine(from: rawLine))

            if lineEnd < string.length {
                let terminator = string.character(at: lineEnd)
                lineEnd += 1
                if terminator == 0x0D, lineEnd < string.length, string.character(at: lineEnd) == 0x0A {
                    lineEnd += 1
                }
            }
            lineStart = lineEnd
        }

        if string.length > 0 {
            let lastCharacter = string.substring(with: NSRange(location: string.length - 1, length: 1))
            if lastCharacter == "\n" || lastCharacter == "\r" {
                lines.append(parsedLine(from: NSAttributedString(string: "")))
            }
        }

        var index = 0
        return RichDocument(blocks: buildBlocks(from: lines, startingAt: &index, depth: 0))
    }

    private struct ParsedAttributedLine {
        var depth: Int
        var block: RichBlock
    }

    private static func parsedLine(from line: NSAttributedString) -> ParsedAttributedLine {
        let depth: Int
        if line.length > 0 {
            depth = intAttribute(RichDocumentAttributeKeys.elementDepth, in: line) ?? 0
        } else {
            depth = 0
        }
        return ParsedAttributedLine(depth: max(0, depth), block: block(from: line))
    }

    private static func buildBlocks(
        from lines: [ParsedAttributedLine],
        startingAt index: inout Int,
        depth: Int
    ) -> [RichBlock] {
        var blocks: [RichBlock] = []

        while index < lines.count {
            let line = lines[index]
            if line.depth < depth {
                break
            }

            if line.depth > depth, blocks.last?.kind == .element {
                var parent = blocks.removeLast()
                let nested = buildBlocks(from: lines, startingAt: &index, depth: line.depth)
                if !nested.isEmpty {
                    parent.children = nested
                }
                blocks.append(parent)
                continue
            }

            var block = line.block
            index += 1

            if block.kind == .element {
                let nested = buildBlocks(from: lines, startingAt: &index, depth: line.depth + 1)
                if !nested.isEmpty {
                    block.children = nested
                }
            }

            blocks.append(block)
        }

        return blocks
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

        if let element = elementBlock(from: line) {
            return element
        }

        // Detect headings by custom attribute (preferred over text prefix)
        if line.length > 0,
           let level = line.attribute(RichDocumentAttributeKeys.headingLevel, at: 0, effectiveRange: nil) as? Int {
            let kind: RichBlockKind = level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3
            let id = uuidAttribute(RichDocumentAttributeKeys.headingBlockID, in: line) ?? UUID()
            let collapsed = boolAttribute(RichDocumentAttributeKeys.headingCollapsed, in: line) ?? false
            let collapsedBlocks = headingCollapsedBlocksAttribute(from: line)
            // Strings serialized before the plain/toggle split carry no
            // collapsible attribute — same fallback as metadata decoding: a
            // folded section must keep its affordance so the hidden blocks
            // stay reachable.
            let collapsible = boolAttribute(RichDocumentAttributeKeys.headingCollapsible, in: line)
                ?? (collapsed || !collapsedBlocks.isEmpty)
            return RichBlock(
                id: id,
                kind: kind,
                inlines: inlineNodes(from: line),
                heading: RichHeadingMetadata(
                    isCollapsed: collapsed,
                    collapsedBlocks: collapsedBlocks,
                    isCollapsible: collapsible
                )
            )
        }

        // Fallback: detect by text prefix (backward compat for legacy documents)
        let (kind, contentStart, checked) = blockDescriptor(for: text)
        let contentRange = NSRange(location: min(contentStart, line.length), length: max(0, line.length - min(contentStart, line.length)))
        let content = line.attributedSubstring(from: contentRange)
        var inlines = inlineNodes(from: content)
        if kind == .checklist, checked == true {
            // The serializer draws checked items struck through; strip it here
            // so the strikethrough never becomes a persistent content mark.
            for index in inlines.indices where inlines[index].kind == .text {
                inlines[index].marks.remove(.strikethrough)
            }
        }
        return RichBlock(kind: kind, inlines: inlines, checked: checked)
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

    private static func elementBlock(from line: NSAttributedString) -> RichBlock? {
        guard line.length > 0,
              let definitionID = uuidAttribute(RichDocumentAttributeKeys.elementDefinitionID, in: line) else {
            return nil
        }

        let instanceID = uuidAttribute(RichDocumentAttributeKeys.elementInstanceID, in: line) ?? UUID()
        let elementName = stringAttribute(RichDocumentAttributeKeys.elementTitle, in: line)
            ?? line.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let instanceTitle = stringAttribute(RichDocumentAttributeKeys.elementInstanceTitle, in: line)
            ?? line.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = stringAttribute(RichDocumentAttributeKeys.elementIcon, in: line) ?? DocumentElementSymbol.fallback
        let collapsed = boolAttribute(RichDocumentAttributeKeys.elementCollapsed, in: line) ?? false
        let children = elementChildrenAttribute(from: line)
        let instance = RichElementInstance(
            id: instanceID,
            definitionID: definitionID,
            titleSnapshot: elementName.isEmpty ? "Untitled Element" : elementName,
            systemIconSnapshot: DocumentElementSymbol.validName(icon),
            isCollapsed: collapsed,
            instanceTitleSnapshot: instanceTitle.isEmpty ? elementName : instanceTitle
        )
        return RichBlock.element(instance, children: children)
    }

    private static func elementChildrenAttribute(from line: NSAttributedString) -> [RichBlock] {
        guard let json = stringAttribute(RichDocumentAttributeKeys.elementChildrenJSON, in: line),
              let data = json.data(using: .utf8),
              let children = try? JSONDecoder().decode([RichBlock].self, from: data) else {
            return []
        }
        return children
    }

    private static func headingCollapsedBlocksAttribute(from line: NSAttributedString) -> [RichBlock] {
        guard let json = stringAttribute(RichDocumentAttributeKeys.headingCollapsedChildrenJSON, in: line),
              let data = json.data(using: .utf8),
              let blocks = try? JSONDecoder().decode([RichBlock].self, from: data) else {
            return []
        }
        return blocks
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

    private static func stringAttribute(_ key: NSAttributedString.Key, in line: NSAttributedString) -> String? {
        guard line.length > 0 else { return nil }
        if let value = line.attribute(key, at: 0, effectiveRange: nil) as? String {
            return value
        }
        return nil
    }

    private static func uuidAttribute(_ key: NSAttributedString.Key, in line: NSAttributedString) -> UUID? {
        guard line.length > 0 else { return nil }
        if let value = line.attribute(key, at: 0, effectiveRange: nil) as? UUID {
            return value
        }
        if let value = line.attribute(key, at: 0, effectiveRange: nil) as? String {
            return UUID(uuidString: value)
        }
        return nil
    }

    private static func intAttribute(_ key: NSAttributedString.Key, in line: NSAttributedString) -> Int? {
        guard line.length > 0 else { return nil }
        if let value = line.attribute(key, at: 0, effectiveRange: nil) as? Int {
            return value
        }
        if let value = line.attribute(key, at: 0, effectiveRange: nil) as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func boolAttribute(_ key: NSAttributedString.Key, in line: NSAttributedString) -> Bool? {
        guard line.length > 0 else { return nil }
        if let value = line.attribute(key, at: 0, effectiveRange: nil) as? Bool {
            return value
        }
        if let value = line.attribute(key, at: 0, effectiveRange: nil) as? NSNumber {
            return value.boolValue
        }
        return nil
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
        // The user-chosen display width rides along as an attribute on the attachment so it
        // survives editing in the live text view; it is persisted via RichImageReference.
        let displayWidth = (attributes[RichDocumentAttributeKeys.imageDisplayWidth] as? NSNumber).map { CGFloat($0.doubleValue) }

        if let existingPath = attributes[RichDocumentAttributeKeys.imagePath] as? String,
           let image = ImageStore.load(path: existingPath) {
            let size = image.size
            return RichImageReference(path: existingPath, width: size.width, height: size.height, displayWidth: displayWidth)
        }

        let data = attachment.fileWrapper?.regularFileContents ?? attachment.image?.pngData() ?? attachment.image?.tiffRepresentation
        guard let data else {
            return nil
        }

        let filename = attachment.fileWrapper?.preferredFilename
        guard let saved = try? ImageStore.save(data, originalFilename: filename) else {
            return nil
        }

        return RichImageReference(path: saved.path, width: saved.width, height: saved.height, displayWidth: displayWidth)
    }

    private static func imageAttachment(for image: RichImageReference) -> NSTextAttachment? {
        // Display math reads the STORED reference dims (never decoded pixels)
        // so cached and freshly-decoded paths lay out identically.
        let intrinsic = CGSize(width: image.width, height: image.height)
        let display = ImageResizeMath.resolvedSize(displayWidth: image.displayWidth, intrinsic: intrinsic, maxWidth: 680)

        // The scaled bitmap is cached per path+mtime+targetWidth so
        // syncEditorForPresentationChange doesn't re-rasterize every image
        // on each rebuild.
        let targetWidth = min(680, image.width)
        let scaledDiscriminator = "scaled|\(targetWidth)"
        let scaled: NSImage
        if let cachedScaled = ImageStore.cachedDerivedImage(path: image.path, discriminator: scaledDiscriminator) {
            scaled = cachedScaled
        } else {
            guard let nsImage = ImageStore.load(path: image.path) else {
                return nil
            }
            // Keep a crisp bitmap (scaled to the historical cap), but let `bounds` drive the
            // on-screen size so resizing is a pure layout change — no image re-decode.
            scaled = nsImage.scaled(toFit: CGSize(width: targetWidth, height: 10_000))
            ImageStore.storeDerivedImage(scaled, path: image.path, discriminator: scaledDiscriminator)
        }

        let attachment = NSTextAttachment()
        attachment.image = scaled
        attachment.bounds = CGRect(origin: .zero, size: display)
        return attachment
    }

    private static func imageFallbackAttributedString(fontSize: CGFloat, darkMode: Bool) -> NSAttributedString {
        let color = darkMode ? NSColor.white.withAlphaComponent(0.65) : NSColor(DS.documentTextSecondary)
        return NSAttributedString(string: "[Image]", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color
        ])
    }

    private static func elementHeaderAttributedString(for block: RichBlock, depth: Int, fontSize: CGFloat, darkMode: Bool) -> NSAttributedString {
        let fallback = block.element?.titleSnapshot ?? "Untitled"
        let instanceTitle = block.element?.instanceTitleSnapshot ?? fallback
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.minimumLineHeight = DocumentElementHeaderLayout.headerHeight
        paragraphStyle.maximumLineHeight = DocumentElementHeaderLayout.headerHeight
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.paragraphSpacingBefore = 6
        let titleInset = DocumentElementHeaderLayout.titleLeadingInset(
            depth: depth,
            fontSize: fontSize
        )
        paragraphStyle.firstLineHeadIndent = titleInset
        paragraphStyle.headIndent = titleInset

        var attributes: [NSAttributedString.Key: Any] = [
            // The card's title must outrank the body it introduces (it sat at
            // 13.5 medium under 17pt body — the block set's clearest
            // hierarchy inversion). Full ink: rungs, never alphas.
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: darkMode ? NSColor.white : NSColor(DS.documentText),
            .paragraphStyle: paragraphStyle,
            RichDocumentAttributeKeys.elementDepth: depth
        ]

        if let element = block.element {
            attributes[RichDocumentAttributeKeys.elementInstanceID] = element.id.uuidString
            attributes[RichDocumentAttributeKeys.elementDefinitionID] = element.definitionID.uuidString
            attributes[RichDocumentAttributeKeys.elementTitle] = element.titleSnapshot
            attributes[RichDocumentAttributeKeys.elementInstanceTitle] = element.instanceTitleSnapshot
            attributes[RichDocumentAttributeKeys.elementIcon] = DocumentElementSymbol.validName(element.systemIconSnapshot)
            attributes[RichDocumentAttributeKeys.elementCollapsed] = NSNumber(value: element.isCollapsed)
        }

        if !block.children.isEmpty,
           let data = try? JSONEncoder().encode(block.children),
           let json = String(data: data, encoding: .utf8) {
            attributes[RichDocumentAttributeKeys.elementChildrenJSON] = json
        }

        return NSAttributedString(string: instanceTitle, attributes: attributes)
    }

    private static func addDepth(_ depth: Int, to attributedString: NSMutableAttributedString, from start: Int) {
        let length = attributedString.length - start
        guard length > 0 else { return }
        attributedString.addAttribute(
            RichDocumentAttributeKeys.elementDepth,
            value: depth,
            range: NSRange(location: start, length: length)
        )
    }

    private static let childContentIndent: CGFloat = 16

    private static func applyChildIndent(
        to attributedString: NSMutableAttributedString,
        from start: Int,
        depth: Int,
        fontSize: CGFloat
    ) {
        let length = attributedString.length - start
        guard length > 0 else { return }
        let range = NSRange(location: start, length: length)
        let nestedInset = CGFloat(max(0, depth - 1)) * DocumentElementHeaderLayout.nestedIndent
        let indent = DocumentElementHeaderLayout.leadingPadding + nestedInset + childContentIndent

        attributedString.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subRange, _ in
            let base = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let isElementHeader = attributedString.attribute(
                RichDocumentAttributeKeys.elementDefinitionID,
                at: subRange.location,
                effectiveRange: nil
            ) != nil
            if isElementHeader { return }

            guard let updated = base.mutableCopy() as? NSMutableParagraphStyle else { return }
            updated.firstLineHeadIndent = indent
            updated.headIndent = indent
            attributedString.addAttribute(.paragraphStyle, value: updated, range: subRange)
        }
    }

    private static func attributesWithDepth(
        _ attributes: [NSAttributedString.Key: Any],
        depth: Int
    ) -> [NSAttributedString.Key: Any] {
        var result = attributes
        result[RichDocumentAttributeKeys.elementDepth] = depth
        return result
    }

    private static func blockPrefix(for block: RichBlock, listPosition: Int) -> String {
        switch block.kind {
        case .paragraph, .image, .element, .content, .research, .callout, .toggle, .code, .sketch:
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
        switch block.kind {
        case .quote:
            // The bar speaks the page's one rule voice (border tokens at
            // real weight) — a light-weight 0.7-alpha pipe read as a typo.
            return [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: darkMode ? NSColor(DS.focusImmersiveBorder) : NSColor(DS.documentBorder)
            ]
        case .checklist:
            var attributes = baseAttributes(
                fontSize: fontSize,
                darkMode: darkMode,
                singleLine: singleLine,
                baseFontWeight: baseFontWeight,
                titleMode: titleMode
            )
            if block.checked == true {
                attributes[.foregroundColor] = NSColor(CosmoColors.cosmoAI).withAlphaComponent(darkMode ? 0.92 : 0.85)
            }
            return attributes
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
            .foregroundColor: darkMode ? NSColor.white : NSColor(DS.documentText),
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

        // Quote content keeps full ink — the inset bar alone marks the kind
        // (the 0.9 alpha was the last stack on an ink rung).

        // Code reads as a compact mono column — tight leading, no paragraph
        // air (soft-break lines inside the block should sit close).
        if block.kind == .code {
            let codeParagraph = NSMutableParagraphStyle()
            codeParagraph.lineSpacing = 3
            codeParagraph.paragraphSpacing = 0
            attributes[.paragraphStyle] = codeParagraph
        }

        // Completed to-dos read as done: muted ink plus a strikethrough drawn
        // at render time. The parser strips this strikethrough on checked
        // lines so toggling never bakes a persistent mark into the content.
        if block.kind == .checklist, block.checked == true {
            // Dim once, but stay legible — 0.45 sat under 3:1 on parchment.
            attributes[.foregroundColor] = (attributes[.foregroundColor] as? NSColor)?.withAlphaComponent(0.55)
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        // Headings: embed level attribute + paragraph spacing for round-trip detection
        if let headingLevel = block.kind.headingLevelInt, !titleMode {
            let isCollapsible = block.heading?.isCollapsible ?? false
            attributes[RichDocumentAttributeKeys.headingLevel] = headingLevel
            attributes[RichDocumentAttributeKeys.headingBlockID] = block.id.uuidString
            attributes[RichDocumentAttributeKeys.headingCollapsed] = NSNumber(value: block.heading?.isCollapsed ?? false)
            attributes[RichDocumentAttributeKeys.headingCollapsible] = NSNumber(value: isCollapsible)
            if let collapsedBlocks = block.heading?.collapsedBlocks,
               !collapsedBlocks.isEmpty,
               let data = try? JSONEncoder().encode(collapsedBlocks),
               let json = String(data: data, encoding: .utf8) {
                attributes[RichDocumentAttributeKeys.headingCollapsedChildrenJSON] = json
            }
            let headingParagraph = NSMutableParagraphStyle()
            headingParagraph.lineSpacing = 4
            headingParagraph.paragraphSpacing = 12
            // Only collapsible headings reserve the chevron gutter — plain
            // headings sit flush with body text.
            let headingGutter: CGFloat = isCollapsible ? 34 : 0
            headingParagraph.firstLineHeadIndent = headingGutter
            headingParagraph.headIndent = headingGutter
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
        // Modular heading ladder (~1.24 scale, jury round 1): 31/25/20 at the
        // 17pt default, monotone under the page title (38) at every text size.
        // H1 is SEMIBOLD so weight, not just size, separates it from the bold
        // title (at Large they sit 38/34). GUARD-TWINS: applyHeading and
        // seedTypingAttributesForEmptyRow (TextKitCoordinator) and
        // BlockStaticRowPlaceholder.editorFont duplicate this table — change
        // all FOUR together.
        case .heading1:
            return NSFont.systemFont(ofSize: min(34, (fontSize * 1.85).rounded()), weight: .semibold)
        case .heading2:
            return NSFont.systemFont(ofSize: (fontSize * 1.45).rounded(), weight: .semibold)
        case .heading3:
            return NSFont.systemFont(ofSize: (fontSize * 1.20).rounded(), weight: .medium)
        case .code:
            return NSFont.monospacedSystemFont(ofSize: max(11, fontSize - 3), weight: .regular)
        case .toggle:
            return NSFont.systemFont(ofSize: fontSize, weight: .medium)
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
