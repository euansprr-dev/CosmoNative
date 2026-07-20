// CosmoOS/UI/FocusMode/Connection/ConceptMentionToken.swift
// One mention grammar for concept items, shared by the concept collaborator's
// staged edits and the quick-add @ menu. Staged text carries explicit tokens —
// `@[Title](connection:<uuid>)` — which resolve at apply time into
// RichDocument mention inlines, so item text stays a clean plain-text
// projection ("@Title") while the link survives renames and cross-dive moves.

import Foundation

enum ConceptMentionToken {

    /// A staged item resolved into its persistable parts.
    struct ParsedItem {
        var plainText: String
        var document: RichDocument
        var mentions: [RichMention]

        /// Set when the whole item is a single connection mention — the item
        /// then persists as a first-class link row (`linkedConnectionUUID`),
        /// same shape the mint service writes.
        var soleConnectionLink: RichMention?
    }

    /// `@[Title](connection:<uuid>)` — the type segment is optional and
    /// defaults to connection, so `@[Title](<uuid>)` also resolves.
    private static let tokenPattern = #"@\[([^\]\n]+)\]\((?:([A-Za-z_]+):)?([0-9A-Za-z\-]{8,})\)"#

    private static let regex = try? NSRegularExpression(pattern: tokenPattern)

    static func containsToken(_ text: String) -> Bool {
        guard let regex, text.contains("@[") else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Resolves an item's staged text. Text without tokens round-trips through
    /// the legacy migration path unchanged.
    static func parse(_ text: String) -> ParsedItem {
        guard let regex, containsToken(text) else {
            return ParsedItem(
                plainText: text,
                document: RichDocument.migrateLegacy(text),
                mentions: [],
                soleConnectionLink: nil
            )
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        var inlines: [RichInlineNode] = []
        var mentions: [RichMention] = []
        var plain = ""
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let run = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                inlines.append(.text(run))
                plain += run
            }
            let title = ns.substring(with: match.range(at: 1))
            let typeRaw = match.range(at: 2).location == NSNotFound
                ? "connection"
                : ns.substring(with: match.range(at: 2))
            let mention = RichMention(
                entityUUID: ns.substring(with: match.range(at: 3)),
                entityID: nil,
                entityType: EntityType(rawValue: typeRaw) ?? .connection,
                titleSnapshot: title
            )
            inlines.append(.mention(mention))
            mentions.append(mention)
            plain += mention.displayText
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            let run = ns.substring(from: cursor)
            inlines.append(.text(run))
            plain += run
        }

        let soleLink: RichMention? = {
            guard matches.count == 1, mentions.first?.entityType == .connection else { return nil }
            let outside = plain.replacingOccurrences(of: mentions[0].displayText, with: "")
            return outside.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? mentions[0] : nil
        }()

        return ParsedItem(
            plainText: plain,
            document: RichDocument(blocks: [RichBlock(kind: .paragraph, inlines: inlines)]),
            mentions: mentions,
            soleConnectionLink: soleLink
        )
    }

    /// Display projection for staged-text previews (ghost rows, diff cards):
    /// tokens read as "@Title" before they're accepted.
    static func displayText(_ text: String) -> String {
        parse(text).plainText
    }

    /// Every mention inline in a document, document order — the render-time
    /// input for linkifying "@Title" runs in item rows.
    static func mentions(in document: RichDocument) -> [RichMention] {
        collectMentions(in: document.blocks)
    }

    private static func collectMentions(in blocks: [RichBlock]) -> [RichMention] {
        blocks.flatMap { block in
            block.inlines.compactMap { $0.kind == .mention ? $0.mention : nil }
                + collectMentions(in: block.children)
        }
    }

    /// Builds an item document from quick-add text whose mentions were picked
    /// via the @ menu: each mention's "@Title" run becomes a mention inline,
    /// resolved longest-title-first so overlapping titles claim correctly.
    static func document(text: String, mentions: [RichMention]) -> ParsedItem {
        guard !mentions.isEmpty else {
            return ParsedItem(
                plainText: text,
                document: RichDocument.migrateLegacy(text),
                mentions: [],
                soleConnectionLink: nil
            )
        }
        var tokenized = text
        for mention in mentions.sorted(by: { $0.titleSnapshot.count > $1.titleSnapshot.count }) {
            let token = "@[\(mention.titleSnapshot)](\(mention.entityType.rawValue):\(mention.entityUUID))"
            if let range = tokenized.range(of: mention.displayText) {
                tokenized.replaceSubrange(range, with: token)
            }
        }
        return parse(tokenized)
    }
}

extension ConnectionItem {
    /// Mentions persisted on this item — feed these to the linked-text views
    /// so "@Title" runs render as tappable pills.
    var explicitMentions: [RichMention] {
        guard let document else { return [] }
        return ConceptMentionToken.mentions(in: document)
    }
}
