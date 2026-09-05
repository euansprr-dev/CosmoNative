// TWIN FILE — byte-identical in CosmoOS-Swift/Editor/Clipboard and
// CosmoOS-iOS/CosmoCoreKit/Sources/Clipboard. Verified by Tools/verify_twins.sh.
//
// A tolerant HTML reader: tokenizer + tree builder in pure Swift, no WebKit,
// no libxml. It exists so the paste pipeline can read the HTML flavour that
// Google Docs, Sheets, Excel, Numbers, Notion and Safari put on the
// pasteboard without touching a web view. It never throws, never loops
// forever, and handles a megabyte of tag soup in well under a second: the
// tokenizer walks UTF-8 bytes with a single index that only moves forward,
// and the open-element stack is bounded.
//
// It is NOT a spec-complete HTML5 parser. It implements the subset of
// implicit-close rules that real clipboard HTML relies on (see
// `ImplicitClose`), keeps raw text in `#text` nodes (whitespace is the
// importer's job), and drops the contents of `script`, `style`, `head`,
// `template` and `noscript`.

import Foundation

/// One node of the light DOM. Elements carry a lowercased `name` and
/// lowercased attribute keys; text nodes are named `"#text"` and carry their
/// (entity-decoded, otherwise raw) `text`; the root is `"#document"`.
public final class HTMLNode {
    public var name: String
    public var attributes: [String: String]
    public var children: [HTMLNode]
    public var text: String
    public weak var parent: HTMLNode?

    private var cachedStyle: (source: String, value: [String: String])?

    public init(name: String, attributes: [String: String] = [:], text: String = "") {
        self.name = name
        self.attributes = attributes
        self.children = []
        self.text = text
    }

    public static let textNodeName = "#text"
    public static let documentNodeName = "#document"

    public var isText: Bool { name == HTMLNode.textNodeName }
    public var isElement: Bool { !isText && name != HTMLNode.documentNodeName }

    public func appendChild(_ child: HTMLNode) {
        child.parent = self
        children.append(child)
    }

    /// The attribute value for a (case-insensitive) name, nil when absent.
    public func attr(_ name: String) -> String? {
        attributes[name.lowercased()]
    }

    /// Whether the attribute exists at all (valueless attributes are stored
    /// with an empty string).
    public func hasAttr(_ name: String) -> Bool {
        attributes[name.lowercased()] != nil
    }

    /// The `class` attribute split into tokens.
    public var classNames: [String] {
        (attr("class") ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).map(String.init)
    }

    public func hasClass(_ token: String) -> Bool {
        let wanted = token.lowercased()
        return classNames.contains { $0.lowercased() == wanted }
    }

    /// The `style` attribute parsed into `property: value` pairs. Property
    /// names are lowercased and trimmed; values are trimmed but otherwise
    /// left as written. A property repeated later in the string wins.
    public var style: [String: String] {
        let source = attributes["style"] ?? ""
        if let cached = cachedStyle, cached.source == source { return cached.value }
        let parsed = HTMLNode.parseStyle(source)
        cachedStyle = (source, parsed)
        return parsed
    }

    /// Element children only (no text nodes).
    public var elementChildren: [HTMLNode] {
        children.filter { $0.isElement }
    }

    public func firstChild(named name: String) -> HTMLNode? {
        let wanted = name.lowercased()
        return children.first { $0.name == wanted }
    }

    /// Every descendant element with this name, in document order.
    /// Iterative so a pathological depth cannot overflow the call stack.
    public func descendants(named name: String) -> [HTMLNode] {
        let wanted = name.lowercased()
        var result: [HTMLNode] = []
        var pending: [HTMLNode] = children.reversed()
        while let node = pending.popLast() {
            if node.name == wanted { result.append(node) }
            if !node.children.isEmpty { pending.append(contentsOf: node.children.reversed()) }
        }
        return result
    }

    /// All descendant text concatenated with runs of whitespace collapsed to
    /// one space and the ends trimmed. `<br>` counts as a space.
    public var innerText: String {
        var raw = ""
        var pending: [HTMLNode] = children.reversed()
        while let node = pending.popLast() {
            if node.isText {
                raw.append(node.text)
            } else if node.name == "br" {
                raw.append(" ")
            }
            if !node.children.isEmpty { pending.append(contentsOf: node.children.reversed()) }
        }
        return HTMLNode.collapseWhitespace(raw)
    }

    /// Collapses every run of whitespace (including NBSP) to a single space
    /// and trims both ends.
    public static func collapseWhitespace(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf8.count)
        var pendingSpace = false
        for scalar in string.unicodeScalars {
            if HTMLNode.isCollapsibleWhitespace(scalar) {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                pendingSpace = false
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    public static func isCollapsibleWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x09, 0x0A, 0x0D, 0x0C, 0xA0:
            return true
        default:
            return false
        }
    }

    public static func parseStyle(_ source: String) -> [String: String] {
        guard !source.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for declaration in source.split(separator: ";", omittingEmptySubsequences: true) {
            guard let colon = declaration.firstIndex(of: ":") else { continue }
            let name = declaration[declaration.startIndex..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            result[name] = value
        }
        return result
    }
}

// MARK: - Reader

public enum CosmoHTMLReader {
    /// Parses `html` into a tree rooted at a `#document` node. Never throws.
    public static func parse(_ html: String) -> HTMLNode {
        var parser = Parser(bytes: Array(html.utf8))
        return parser.run()
    }

    /// Elements that never take children.
    public static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr",
    ]

    /// Elements whose raw contents run to the matching close tag without
    /// being parsed as markup.
    public static let rawTextElements: Set<String> = ["script", "style"]

    /// Elements whose subtree is thrown away when they close.
    public static let droppedElements: Set<String> = ["head", "template", "noscript", "script", "style"]

    /// Opening one of these closes an open `p`.
    public static let paragraphClosers: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "tr", "td", "th", "blockquote", "pre",
        "hr", "section", "article", "header", "footer", "nav", "aside", "figure", "figcaption", "main", "dl", "dt", "dd",
        "form", "fieldset", "address", "details", "summary", "menu", "center",
    ]

    /// Elements a `head` may contain; anything else closes an open head.
    private static let headContent: Set<String> = ["meta", "link", "style", "script", "title", "base", "noscript", "template"]

    /// The open-element stack never grows past this. Deeper elements are
    /// appended as children of the innermost open element but not pushed,
    /// so their content flows as siblings — never a crash, never a hang.
    public static let maximumDepth = 512

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        let root = HTMLNode(name: HTMLNode.documentNodeName)
        var stack: [HTMLNode] = []

        init(bytes: [UInt8]) {
            self.bytes = bytes
            stack = [root]
        }

        var current: HTMLNode { stack[stack.count - 1] }

        mutating func run() -> HTMLNode {
            let count = bytes.count
            while index < count {
                if bytes[index] == UInt8(ascii: "<") {
                    parseMarkup()
                } else {
                    parseText()
                }
            }
            while stack.count > 1 { pop() }
            return root
        }

        // MARK: Text

        private mutating func parseText() {
            let start = index
            let count = bytes.count
            while index < count, bytes[index] != UInt8(ascii: "<") { index += 1 }
            appendText(CosmoHTMLReader.decodeEntities(bytes[start..<index]))
        }

        private func appendText(_ text: String) {
            guard !text.isEmpty else { return }
            let parent = current
            if let last = parent.children.last, last.isText {
                last.text.append(text)
            } else {
                parent.appendChild(HTMLNode(name: HTMLNode.textNodeName, text: text))
            }
        }

        // MARK: Markup

        private mutating func parseMarkup() {
            let count = bytes.count
            // `<` is at index.
            guard index + 1 < count else {
                appendText("<")
                index = count
                return
            }
            let next = bytes[index + 1]
            if next == UInt8(ascii: "!") {
                if startsWith("<!--") {
                    index += 4
                    skipPast(marker: "-->")
                } else if startsWith("<![CDATA[") {
                    index += 9
                    skipPast(marker: "]]>")
                } else {
                    index += 2
                    skipPast(marker: ">")
                }
                return
            }
            if next == UInt8(ascii: "?") {
                index += 2
                skipPast(marker: ">")
                return
            }
            if next == UInt8(ascii: "/") {
                guard index + 2 < count, isNameStart(bytes[index + 2]) else {
                    // `</>` or `</ 3` — bogus; skip to `>` like a browser.
                    index += 2
                    skipPast(marker: ">")
                    return
                }
                index += 2
                let name = readName()
                skipPast(marker: ">")
                handleClose(name)
                return
            }
            guard isNameStart(next) else {
                appendText("<")
                index += 1
                return
            }
            index += 1
            let name = readName()
            var attributes: [String: String] = [:]
            var selfClosing = false
            readAttributes(into: &attributes, selfClosing: &selfClosing)
            handleOpen(name, attributes: attributes, selfClosing: selfClosing)
        }

        private func startsWith(_ literal: String) -> Bool {
            let pattern = Array(literal.utf8)
            guard index + pattern.count <= bytes.count else { return false }
            for offset in 0..<pattern.count where bytes[index + offset] != pattern[offset] { return false }
            return true
        }

        private mutating func skipPast(marker: String) {
            let pattern = Array(marker.utf8)
            let count = bytes.count
            guard let first = pattern.first else { return }
            while index < count {
                if bytes[index] == first, index + pattern.count <= count {
                    var matches = true
                    for offset in 1..<pattern.count where bytes[index + offset] != pattern[offset] {
                        matches = false
                        break
                    }
                    if matches {
                        index += pattern.count
                        return
                    }
                }
                index += 1
            }
            index = count
        }

        private func isNameStart(_ byte: UInt8) -> Bool {
            (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
        }

        private func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
        }

        /// Reads a tag name (letters, digits, `-`, `_`, `:`, `.`) and
        /// lowercases it.
        private mutating func readName() -> String {
            let start = index
            let count = bytes.count
            while index < count {
                let byte = bytes[index]
                if isWhitespace(byte) || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "/") { break }
                index += 1
            }
            return lowercasedASCII(bytes[start..<index])
        }

        private func lowercasedASCII(_ slice: ArraySlice<UInt8>) -> String {
            var lowered = [UInt8]()
            lowered.reserveCapacity(slice.count)
            for byte in slice {
                lowered.append(byte >= 0x41 && byte <= 0x5A ? byte + 32 : byte)
            }
            return String(decoding: lowered, as: UTF8.self)
        }

        private mutating func readAttributes(into attributes: inout [String: String], selfClosing: inout Bool) {
            let count = bytes.count
            while index < count {
                while index < count, isWhitespace(bytes[index]) { index += 1 }
                guard index < count else { return }
                let byte = bytes[index]
                if byte == UInt8(ascii: ">") {
                    index += 1
                    return
                }
                if byte == UInt8(ascii: "/") {
                    index += 1
                    if index < count, bytes[index] == UInt8(ascii: ">") {
                        selfClosing = true
                        index += 1
                        return
                    }
                    continue
                }
                // Attribute name: everything up to whitespace, `=`, `>` or `/`.
                let nameStart = index
                while index < count {
                    let c = bytes[index]
                    if isWhitespace(c) || c == UInt8(ascii: "=") || c == UInt8(ascii: ">") || c == UInt8(ascii: "/") { break }
                    index += 1
                }
                if index == nameStart {
                    // A stray byte we cannot use (e.g. `=` with no name).
                    index += 1
                    continue
                }
                let name = lowercasedASCII(bytes[nameStart..<index])
                while index < count, isWhitespace(bytes[index]) { index += 1 }
                var value = ""
                if index < count, bytes[index] == UInt8(ascii: "=") {
                    index += 1
                    while index < count, isWhitespace(bytes[index]) { index += 1 }
                    if index < count {
                        let quote = bytes[index]
                        if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                            index += 1
                            let valueStart = index
                            while index < count, bytes[index] != quote { index += 1 }
                            value = CosmoHTMLReader.decodeEntities(bytes[valueStart..<index])
                            if index < count { index += 1 }
                        } else {
                            let valueStart = index
                            while index < count {
                                let c = bytes[index]
                                if isWhitespace(c) || c == UInt8(ascii: ">") { break }
                                index += 1
                            }
                            value = CosmoHTMLReader.decodeEntities(bytes[valueStart..<index])
                        }
                    }
                }
                if attributes[name] == nil { attributes[name] = value }
            }
        }

        // MARK: Tree building

        private mutating func handleOpen(_ name: String, attributes: [String: String], selfClosing: Bool) {
            applyImplicitCloses(for: name)
            let node = HTMLNode(name: name, attributes: attributes)
            current.appendChild(node)
            if CosmoHTMLReader.rawTextElements.contains(name) {
                consumeRawText(until: name, into: node)
                return
            }
            if selfClosing || CosmoHTMLReader.voidElements.contains(name) { return }
            if stack.count < CosmoHTMLReader.maximumDepth {
                stack.append(node)
            }
        }

        /// Runs to the matching `</name` (case-insensitive) without parsing
        /// markup and discards the contents.
        private mutating func consumeRawText(until name: String, into node: HTMLNode) {
            let count = bytes.count
            let pattern = Array(("</" + name).utf8)
            let start = index
            var end = count
            var scan = index
            while scan + pattern.count <= count {
                if bytes[scan] == UInt8(ascii: "<"), bytes[scan + 1] == UInt8(ascii: "/") {
                    var matches = true
                    for offset in 2..<pattern.count {
                        var byte = bytes[scan + offset]
                        if byte >= 0x41 && byte <= 0x5A { byte += 32 }
                        if byte != pattern[offset] {
                            matches = false
                            break
                        }
                    }
                    if matches {
                        end = scan
                        break
                    }
                }
                scan += 1
            }
            // The raw contents are dropped: a `<style>` sheet or a script is
            // never note content.
            _ = start
            index = end
            if end < count {
                // Skip the closing tag itself.
                skipPast(marker: ">")
            }
        }

        private mutating func handleClose(_ name: String) {
            // Find the nearest open element with this name; ignore when none.
            var depth = stack.count - 1
            while depth > 0 {
                if stack[depth].name == name {
                    while stack.count > depth { pop() }
                    return
                }
                depth -= 1
            }
        }

        private mutating func pop() {
            guard stack.count > 1 else { return }
            let node = stack.removeLast()
            if CosmoHTMLReader.droppedElements.contains(node.name) {
                node.children = []
            }
        }

        /// Closes elements the new tag implicitly ends. Each search walks
        /// down from the innermost open element and stops at a scope
        /// boundary so a `<li>` inside a table cell never closes the list
        /// item that holds the table.
        private mutating func applyImplicitCloses(for name: String) {
            // An open head ends when body content begins.
            if current.name == "head", !CosmoHTMLReader.headContent.contains(name) {
                pop()
            }
            if CosmoHTMLReader.paragraphClosers.contains(name) {
                closeNearest(["p"], stoppingAt: ImplicitClose.blockScopeBoundaries)
            }
            switch name {
            case "li":
                closeNearest(["li"], stoppingAt: ImplicitClose.listScopeBoundaries)
            case "dt", "dd":
                closeNearest(["dt", "dd"], stoppingAt: ImplicitClose.definitionScopeBoundaries)
            case "td", "th":
                closeNearest(["td", "th"], stoppingAt: ImplicitClose.rowScopeBoundaries)
            case "tr":
                closeNearest(["tr"], stoppingAt: ImplicitClose.tableScopeBoundaries)
            case "tbody", "thead", "tfoot":
                closeNearest(["tr", "tbody", "thead", "tfoot"], stoppingAt: ImplicitClose.tableScopeBoundaries)
            case "h1", "h2", "h3", "h4", "h5", "h6":
                if ImplicitClose.headings.contains(current.name) { pop() }
            case "option":
                closeNearest(["option"], stoppingAt: ["select", "optgroup", "datalist"])
            default:
                break
            }
        }

        private mutating func closeNearest(_ names: Set<String>, stoppingAt boundaries: Set<String>) {
            var depth = stack.count - 1
            while depth > 0 {
                let candidate = stack[depth].name
                if names.contains(candidate) {
                    while stack.count > depth { pop() }
                    return
                }
                if boundaries.contains(candidate) { return }
                depth -= 1
            }
        }
    }

    /// Scope boundaries for the implicit-close searches.
    public enum ImplicitClose {
        public static let headings: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
        public static let blockScopeBoundaries: Set<String> = [
            "table", "td", "th", "caption", "tr", "tbody", "thead", "tfoot", "template", "body", "html",
        ]
        public static let listScopeBoundaries: Set<String> = [
            "ul", "ol", "menu", "table", "td", "th", "caption", "template", "body", "html",
        ]
        public static let definitionScopeBoundaries: Set<String> = [
            "dl", "table", "td", "th", "caption", "template", "body", "html",
        ]
        public static let rowScopeBoundaries: Set<String> = ["tr", "table", "tbody", "thead", "tfoot", "template", "body", "html"]
        public static let tableScopeBoundaries: Set<String> = ["table", "template", "body", "html"]
    }

    // MARK: - Entities

    /// Decodes named (HTML4 set plus the common HTML5 aliases) and numeric
    /// character references. Unknown references are kept literally.
    public static func decodeEntities(_ slice: ArraySlice<UInt8>) -> String {
        guard slice.contains(UInt8(ascii: "&")) else {
            return String(decoding: slice, as: UTF8.self)
        }
        var output = [UInt8]()
        output.reserveCapacity(slice.count)
        var i = slice.startIndex
        let end = slice.endIndex
        while i < end {
            let byte = slice[i]
            guard byte == UInt8(ascii: "&") else {
                output.append(byte)
                i += 1
                continue
            }
            // Find the terminating `;` within a short window.
            var j = i + 1
            var found = false
            while j < end, j - i <= 40 {
                let c = slice[j]
                if c == UInt8(ascii: ";") {
                    found = true
                    break
                }
                let alnum = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == UInt8(ascii: "#")
                if !alnum { break }
                j += 1
            }
            guard found, j > i + 1 else {
                output.append(byte)
                i += 1
                continue
            }
            let body = slice[(i + 1)..<j]
            if let scalar = decodeReference(body) {
                output.append(contentsOf: Array(String(scalar).utf8))
                i = j + 1
            } else {
                output.append(byte)
                i += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    public static func decodeEntities(_ string: String) -> String {
        decodeEntities(ArraySlice(Array(string.utf8)))
    }

    private static func decodeReference(_ body: ArraySlice<UInt8>) -> Unicode.Scalar? {
        guard let first = body.first else { return nil }
        if first == UInt8(ascii: "#") {
            var digits = body.dropFirst()
            var radix: UInt32 = 10
            if let marker = digits.first, marker == UInt8(ascii: "x") || marker == UInt8(ascii: "X") {
                radix = 16
                digits = digits.dropFirst()
            }
            guard !digits.isEmpty, digits.count <= 8 else { return nil }
            var value: UInt32 = 0
            for c in digits {
                let digit: UInt32
                switch c {
                case 0x30...0x39: digit = UInt32(c - 0x30)
                case 0x41...0x46: digit = UInt32(c - 0x41 + 10)
                case 0x61...0x66: digit = UInt32(c - 0x61 + 10)
                default: return nil
                }
                guard digit < radix else { return nil }
                value = value &* radix &+ digit
                if value > 0x10FFFF { return replacementCharacter }
            }
            if let remapped = windows1252[value] { return Unicode.Scalar(remapped) ?? replacementCharacter }
            if value == 0 || (value >= 0xD800 && value <= 0xDFFF) { return replacementCharacter }
            return Unicode.Scalar(value) ?? replacementCharacter
        }
        let name = String(decoding: body, as: UTF8.self)
        guard let value = namedEntities[name] else { return nil }
        return Unicode.Scalar(value)
    }

    private static let replacementCharacter: Unicode.Scalar = "\u{FFFD}"

    /// Code points 0x80–0x9F in numeric references mean Windows-1252
    /// glyphs in every browser (`&#146;` is a right single quote).
    private static let windows1252: [UInt32: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
        0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018,
        0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
        0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]

    /// The HTML4 named character references plus the HTML5 aliases that
    /// show up in clipboard HTML (`apos`, `nbsp` variants, arrows, `check`).
    public static let namedEntities: [String: UInt32] = [
        // Markup
        "amp": 0x26, "lt": 0x3C, "gt": 0x3E, "quot": 0x22, "apos": 0x27,
        // Latin-1
        "nbsp": 0xA0, "iexcl": 0xA1, "cent": 0xA2, "pound": 0xA3, "curren": 0xA4, "yen": 0xA5, "brvbar": 0xA6,
        "sect": 0xA7, "uml": 0xA8, "copy": 0xA9, "ordf": 0xAA, "laquo": 0xAB, "not": 0xAC, "shy": 0xAD, "reg": 0xAE,
        "macr": 0xAF, "deg": 0xB0, "plusmn": 0xB1, "sup2": 0xB2, "sup3": 0xB3, "acute": 0xB4, "micro": 0xB5,
        "para": 0xB6, "middot": 0xB7, "cedil": 0xB8, "sup1": 0xB9, "ordm": 0xBA, "raquo": 0xBB, "frac14": 0xBC,
        "frac12": 0xBD, "frac34": 0xBE, "iquest": 0xBF, "Agrave": 0xC0, "Aacute": 0xC1, "Acirc": 0xC2, "Atilde": 0xC3,
        "Auml": 0xC4, "Aring": 0xC5, "AElig": 0xC6, "Ccedil": 0xC7, "Egrave": 0xC8, "Eacute": 0xC9, "Ecirc": 0xCA,
        "Euml": 0xCB, "Igrave": 0xCC, "Iacute": 0xCD, "Icirc": 0xCE, "Iuml": 0xCF, "ETH": 0xD0, "Ntilde": 0xD1,
        "Ograve": 0xD2, "Oacute": 0xD3, "Ocirc": 0xD4, "Otilde": 0xD5, "Ouml": 0xD6, "times": 0xD7, "Oslash": 0xD8,
        "Ugrave": 0xD9, "Uacute": 0xDA, "Ucirc": 0xDB, "Uuml": 0xDC, "Yacute": 0xDD, "THORN": 0xDE, "szlig": 0xDF,
        "agrave": 0xE0, "aacute": 0xE1, "acirc": 0xE2, "atilde": 0xE3, "auml": 0xE4, "aring": 0xE5, "aelig": 0xE6,
        "ccedil": 0xE7, "egrave": 0xE8, "eacute": 0xE9, "ecirc": 0xEA, "euml": 0xEB, "igrave": 0xEC, "iacute": 0xED,
        "icirc": 0xEE, "iuml": 0xEF, "eth": 0xF0, "ntilde": 0xF1, "ograve": 0xF2, "oacute": 0xF3, "ocirc": 0xF4,
        "otilde": 0xF5, "ouml": 0xF6, "divide": 0xF7, "oslash": 0xF8, "ugrave": 0xF9, "uacute": 0xFA, "ucirc": 0xFB,
        "uuml": 0xFC, "yacute": 0xFD, "thorn": 0xFE, "yuml": 0xFF,
        // Latin Extended / spacing
        "OElig": 0x152, "oelig": 0x153, "Scaron": 0x160, "scaron": 0x161, "Yuml": 0x178, "fnof": 0x192,
        "circ": 0x2C6, "tilde": 0x2DC,
        // Greek
        "Alpha": 0x391, "Beta": 0x392, "Gamma": 0x393, "Delta": 0x394, "Epsilon": 0x395, "Zeta": 0x396, "Eta": 0x397,
        "Theta": 0x398, "Iota": 0x399, "Kappa": 0x39A, "Lambda": 0x39B, "Mu": 0x39C, "Nu": 0x39D, "Xi": 0x39E,
        "Omicron": 0x39F, "Pi": 0x3A0, "Rho": 0x3A1, "Sigma": 0x3A3, "Tau": 0x3A4, "Upsilon": 0x3A5, "Phi": 0x3A6,
        "Chi": 0x3A7, "Psi": 0x3A8, "Omega": 0x3A9, "alpha": 0x3B1, "beta": 0x3B2, "gamma": 0x3B3, "delta": 0x3B4,
        "epsilon": 0x3B5, "zeta": 0x3B6, "eta": 0x3B7, "theta": 0x3B8, "iota": 0x3B9, "kappa": 0x3BA, "lambda": 0x3BB,
        "mu": 0x3BC, "nu": 0x3BD, "xi": 0x3BE, "omicron": 0x3BF, "pi": 0x3C0, "rho": 0x3C1, "sigmaf": 0x3C2,
        "sigma": 0x3C3, "tau": 0x3C4, "upsilon": 0x3C5, "phi": 0x3C6, "chi": 0x3C7, "psi": 0x3C8, "omega": 0x3C9,
        "thetasym": 0x3D1, "upsih": 0x3D2, "piv": 0x3D6,
        // Punctuation and symbols
        "ensp": 0x2002, "emsp": 0x2003, "thinsp": 0x2009, "zwnj": 0x200C, "zwj": 0x200D, "lrm": 0x200E, "rlm": 0x200F,
        "ndash": 0x2013, "mdash": 0x2014, "lsquo": 0x2018, "rsquo": 0x2019, "sbquo": 0x201A, "ldquo": 0x201C,
        "rdquo": 0x201D, "bdquo": 0x201E, "dagger": 0x2020, "Dagger": 0x2021, "bull": 0x2022, "hellip": 0x2026,
        "permil": 0x2030, "prime": 0x2032, "Prime": 0x2033, "lsaquo": 0x2039, "rsaquo": 0x203A, "oline": 0x203E,
        "frasl": 0x2044, "euro": 0x20AC, "image": 0x2111, "weierp": 0x2118, "real": 0x211C, "trade": 0x2122,
        "alefsym": 0x2135, "larr": 0x2190, "uarr": 0x2191, "rarr": 0x2192, "darr": 0x2193, "harr": 0x2194,
        "crarr": 0x21B5, "lArr": 0x21D0, "uArr": 0x21D1, "rArr": 0x21D2, "dArr": 0x21D3, "hArr": 0x21D4,
        "forall": 0x2200, "part": 0x2202, "exist": 0x2203, "empty": 0x2205, "nabla": 0x2207, "isin": 0x2208,
        "notin": 0x2209, "ni": 0x220B, "prod": 0x220F, "sum": 0x2211, "minus": 0x2212, "lowast": 0x2217,
        "radic": 0x221A, "prop": 0x221D, "infin": 0x221E, "ang": 0x2220, "and": 0x2227, "or": 0x2228, "cap": 0x2229,
        "cup": 0x222A, "int": 0x222B, "there4": 0x2234, "sim": 0x223C, "cong": 0x2245, "asymp": 0x2248, "ne": 0x2260,
        "equiv": 0x2261, "le": 0x2264, "ge": 0x2265, "sub": 0x2282, "sup": 0x2283, "nsub": 0x2284, "sube": 0x2286,
        "supe": 0x2287, "oplus": 0x2295, "otimes": 0x2297, "perp": 0x22A5, "sdot": 0x22C5, "lceil": 0x2308,
        "rceil": 0x2309, "lfloor": 0x230A, "rfloor": 0x230B, "lang": 0x2329, "rang": 0x232A, "loz": 0x25CA,
        "spades": 0x2660, "clubs": 0x2663, "hearts": 0x2665, "diams": 0x2666,
        // HTML5 aliases that appear in clipboard HTML
        "check": 0x2713, "cross": 0x2717, "star": 0x2606, "starf": 0x2605, "hyphen": 0x2010, "dash": 0x2010,
        "NewLine": 0x0A, "Tab": 0x09, "NonBreakingSpace": 0xA0, "half": 0xBD, "half14": 0xBC, "centerdot": 0xB7,
        "copysr": 0x2117, "phone": 0x260E, "female": 0x2640, "male": 0x2642, "sung": 0x266A, "flat": 0x266D,
        "natural": 0x266E, "sharp": 0x266F, "checkmark": 0x2713, "bullet": 0x2022, "excl": 0x21, "num": 0x23,
        "dollar": 0x24, "percnt": 0x25, "lpar": 0x28, "rpar": 0x29, "ast": 0x2A, "plus": 0x2B, "comma": 0x2C,
        "period": 0x2E, "sol": 0x2F, "colon": 0x3A, "semi": 0x3B, "equals": 0x3D, "quest": 0x3F, "commat": 0x40,
        "lsqb": 0x5B, "bsol": 0x5C, "rsqb": 0x5D, "lowbar": 0x5F, "grave": 0x60, "lcub": 0x7B, "verbar": 0x7C,
        "rcub": 0x7D, "hairsp": 0x200A, "numsp": 0x2007, "puncsp": 0x2008, "MediumSpace": 0x205F,
        "ZeroWidthSpace": 0x200B, "laquo14": 0xAB, "rarrw": 0x219D, "leftarrow": 0x2190, "rightarrow": 0x2192,
        "uparrow": 0x2191, "downarrow": 0x2193,
    ]
}
