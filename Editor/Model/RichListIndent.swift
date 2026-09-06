import Foundation

/// Nested-list grammar — the ONE table every render path reads (block rows,
/// the continuous TextKit editor, the read-only renderer, the hydration
/// placeholder, markdown copy). Tab on a list block deepens it one level;
/// ⇧Tab shallows it. The level is a flat `indent` on the block (Google Docs
/// / Craft model), never a children tree: a list stays a run of siblings, so
/// every existing list operation (split, merge, transform, move, paste)
/// keeps working unchanged and the level simply rides along.
///
/// Glyph ladder per level (cycles past three):
///   bullets   •  ◦  ▪
///   numbered  1. a. i.
///   to-dos    ☐ at every level (the box is the glyph)
///
/// GUARD-TWIN: `RichBlockKind.renderedPrefixLength`, the serializer's
/// `blockPrefix`, the parser's `blockDescriptor` and the continuous editor's
/// block-mode detection all resolve through this table — add a glyph here
/// and every path learns it at once.
enum RichListIndent {
    /// Deepest level a block can sit at (six visual levels, 0…5).
    static let maxLevel = 5

    /// Horizontal inset per level, in points. Wide enough that the child's
    /// glyph clears the parent's text column at body sizes.
    static let insetPerLevel: CGFloat = 26

    static func clamped(_ level: Int) -> Int {
        min(max(0, level), maxLevel)
    }

    // MARK: - Bullets

    static let bulletGlyphs: [String] = ["•", "◦", "▪"]

    static func bulletGlyph(level: Int) -> String {
        bulletGlyphs[clamped(level) % bulletGlyphs.count]
    }

    static func bulletPrefix(level: Int) -> String {
        bulletGlyph(level: level) + " "
    }

    /// UTF-16 length of a bullet prefix at the head of `text` (any level's
    /// glyph), 0 when the text carries none.
    static func bulletPrefixLength(in text: String) -> Int {
        for glyph in bulletGlyphs where text.hasPrefix(glyph + " ") {
            return (glyph + " ").utf16.count
        }
        return 0
    }

    /// The level a bullet glyph at the head of `text` implies — nil when the
    /// text carries no bullet prefix. Only the glyph's rung within the cycle
    /// is knowable from text, so the caller resolves with the stored level.
    static func bulletGlyphRung(in text: String) -> Int? {
        for (rung, glyph) in bulletGlyphs.enumerated() where text.hasPrefix(glyph + " ") {
            return rung
        }
        return nil
    }

    // MARK: - Numbered

    enum NumberingStyle: Equatable {
        case decimal
        case lowerAlpha
        case lowerRoman
    }

    static func numberingStyle(level: Int) -> NumberingStyle {
        switch clamped(level) % 3 {
        case 1: return .lowerAlpha
        case 2: return .lowerRoman
        default: return .decimal
        }
    }

    /// "1", "a", "i" — the label for a 1-based position at a level.
    static func numberedLabel(position: Int, level: Int) -> String {
        let position = max(1, position)
        switch numberingStyle(level: level) {
        case .decimal: return String(position)
        case .lowerAlpha: return alphaLabel(position)
        case .lowerRoman: return romanLabel(position)
        }
    }

    static func numberedPrefix(position: Int, level: Int) -> String {
        numberedLabel(position: position, level: level) + ". "
    }

    /// UTF-16 length of a numbered prefix ("12. ", "b. ", "iv. ") at the
    /// head of `text`. Letter labels are only accepted when the caller knows
    /// the line is a numbered item (`allowsAlpha`) — a paragraph starting
    /// "e. g." must never become a list.
    static func numberedPrefixLength(in text: String, allowsAlpha: Bool) -> Int {
        guard let label = numberedLabelToken(in: text, allowsAlpha: allowsAlpha) else { return 0 }
        return label.utf16.count + 2
    }

    /// The 1-based position a numbered prefix at the head of `text` encodes
    /// for a given level, nil when the text carries no such prefix.
    static func numberedPosition(in text: String, level: Int) -> Int? {
        guard let label = numberedLabelToken(in: text, allowsAlpha: numberingStyle(level: level) != .decimal) else {
            return nil
        }
        switch numberingStyle(level: level) {
        case .decimal: return Int(label)
        case .lowerAlpha: return alphaValue(label)
        case .lowerRoman: return romanValue(label) ?? alphaValue(label)
        }
    }

    /// The label token ("12", "b", "iv") when `text` starts with
    /// `<label>. `; digits always, lowercase letters only when allowed — and
    /// even then only label-SHAPED ones (one or two letters, or a canonical
    /// roman numeral): a row can't know its level from the text alone, so
    /// content starting "beta. " must never read as a label.
    private static func numberedLabelToken(in text: String, allowsAlpha: Bool) -> String? {
        var label = ""
        var iterator = text.unicodeScalars.makeIterator()
        var sawDot = false
        while let scalar = iterator.next() {
            if scalar == "." {
                sawDot = true
                break
            }
            let isDigit = scalar.properties.numericType == .decimal && scalar.isASCII
            let isLower = allowsAlpha && scalar.isASCII && scalar.value >= 97 && scalar.value <= 122
            guard isDigit || isLower else { return nil }
            // Labels are homogeneous: digits or letters, never mixed.
            if let first = label.unicodeScalars.first {
                let firstIsDigit = first.properties.numericType == .decimal
                if firstIsDigit != isDigit { return nil }
            }
            if label.utf16.count >= 8 { return nil }
            label.unicodeScalars.append(scalar)
        }
        guard sawDot, !label.isEmpty, let space = iterator.next(), space == " " else { return nil }
        if let first = label.unicodeScalars.first, first.properties.numericType != .decimal {
            guard label.count <= 2 || romanValue(label) != nil else { return nil }
        }
        return label
    }

    static func alphaLabel(_ position: Int) -> String {
        var n = max(1, position)
        var result = ""
        while n > 0 {
            let remainder = (n - 1) % 26
            result = String(UnicodeScalar(UInt8(97 + remainder))) + result
            n = (n - 1) / 26
        }
        return result
    }

    static func alphaValue(_ label: String) -> Int? {
        guard !label.isEmpty else { return nil }
        var value = 0
        for scalar in label.unicodeScalars {
            guard scalar.value >= 97, scalar.value <= 122 else { return nil }
            value = value * 26 + Int(scalar.value - 96)
        }
        return value
    }

    private static let romanTable: [(Int, String)] = [
        (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
        (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
    ]

    static func romanLabel(_ position: Int) -> String {
        var n = max(1, min(position, 3999))
        var result = ""
        for (value, numeral) in romanTable {
            while n >= value {
                result += numeral
                n -= value
            }
        }
        return result
    }

    static func romanValue(_ label: String) -> Int? {
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        guard !label.isEmpty else { return nil }
        var total = 0
        var previous = 0
        for character in label.reversed() {
            guard let value = values[character] else { return nil }
            if value < previous {
                total -= value
            } else {
                total += value
                previous = value
            }
        }
        // Reject labels that aren't canonical ("iiii", "vx") so a stray
        // word like "mix. " never parses as a position.
        return romanLabel(total) == label ? total : nil
    }

    // MARK: - Numbering runs

    /// Per-block 0-based position within its numbered run AT ITS LEVEL. A
    /// deeper item (any list kind) never breaks the run above it — "1., a.,
    /// b., 2." — while a shallower list item or any non-list block resets
    /// everything at and below its level. `seed` continues a run that
    /// reaches the first block (a block row serializes a single-block
    /// document and receives the count of numbered siblings above it).
    static func numberedOrdinals(for blocks: [RichBlock], seed: Int = 0) -> [Int] {
        var ordinals: [Int] = []
        ordinals.reserveCapacity(blocks.count)
        var counters = [Int](repeating: 0, count: maxLevel + 1)
        if let first = blocks.first, first.kind == .numberedList {
            counters[first.listIndentLevel] = max(0, seed)
        }
        for block in blocks {
            let level = block.listIndentLevel
            if block.kind == .numberedList {
                if level < maxLevel {
                    for deeper in (level + 1)...maxLevel {
                        counters[deeper] = 0
                    }
                }
                ordinals.append(counters[level])
                counters[level] += 1
            } else if block.kind.supportsListIndent {
                for at in level...maxLevel {
                    counters[at] = 0
                }
                ordinals.append(0)
            } else {
                counters = [Int](repeating: 0, count: maxLevel + 1)
                ordinals.append(0)
            }
        }
        return ordinals
    }

    // MARK: - Structure

    /// The block at `index` plus the contiguous list blocks below it that sit
    /// strictly deeper — its visual subtree. Tab / ⇧Tab move the whole
    /// subtree so children keep their relationship to the parent.
    static func subtreeRange(in blocks: [RichBlock], at index: Int) -> Range<Int> {
        guard blocks.indices.contains(index) else { return index..<index }
        let level = blocks[index].listIndentLevel
        var end = index + 1
        while end < blocks.count,
              blocks[end].kind.supportsListIndent,
              blocks[end].listIndentLevel > level {
            end += 1
        }
        return index..<end
    }

    /// The deepest level the block at `index` may be indented to: one past
    /// the list item directly above it (the Notion rule — a nested item
    /// needs something to nest under). Zero when the block above is not a
    /// list item.
    static func maxIndentLevel(in blocks: [RichBlock], at index: Int) -> Int {
        guard index > 0, blocks.indices.contains(index) else { return 0 }
        let previous = blocks[index - 1]
        guard previous.kind.supportsListIndent else { return 0 }
        return clamped(previous.listIndentLevel + 1)
    }
}

extension RichBlockKind {
    /// Kinds whose `indent` is meaningful — the three list kinds.
    var supportsListIndent: Bool {
        self == .bulletList || self == .numberedList || self == .checklist
    }
}

extension RichBlock {
    /// The block's nesting level, clamped and zero for non-list kinds.
    var listIndentLevel: Int {
        guard kind.supportsListIndent else { return 0 }
        return RichListIndent.clamped(indent ?? 0)
    }
}
