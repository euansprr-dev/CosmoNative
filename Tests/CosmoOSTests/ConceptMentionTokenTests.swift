// Tests for the concept mention-token grammar: staged @[Title](type:uuid)
// tokens resolving into RichDocument mention inlines, sole-link detection,
// display projection, and the quick-add builder round-trip.

import Testing
import Foundation
@testable import CosmoOS

struct ConceptMentionTokenTests {

    private let uuid = "11111111-2222-3333-4444-555555555555"

    @Test func plainTextRoundTripsWithoutMentions() {
        let parsed = ConceptMentionToken.parse("Closing loops focuses awareness.")
        #expect(parsed.mentions.isEmpty)
        #expect(parsed.plainText == "Closing loops focuses awareness.")
        #expect(parsed.soleConnectionLink == nil)
    }

    @Test func tokenResolvesToMentionInlineAndPlainProjection() {
        let parsed = ConceptMentionToken.parse(
            "This links to @[Closing Loops](connection:\(uuid)) directly."
        )
        #expect(parsed.plainText == "This links to @Closing Loops directly.")
        #expect(parsed.mentions.count == 1)
        #expect(parsed.mentions.first?.entityUUID == uuid)
        #expect(parsed.mentions.first?.entityType == .connection)
        #expect(parsed.mentions.first?.titleSnapshot == "Closing Loops")
        #expect(parsed.soleConnectionLink == nil)

        let inlineKinds = parsed.document.blocks.first?.inlines.map(\.kind)
        #expect(inlineKinds == [.text, .mention, .text])
    }

    @Test func typePrefixDefaultsToConnectionAndHonorsOtherTypes() {
        let bare = ConceptMentionToken.parse("@[Loop](\(uuid)) plus context")
        #expect(bare.mentions.first?.entityType == .connection)

        let note = ConceptMentionToken.parse("see @[My Note](note:\(uuid))")
        #expect(note.mentions.first?.entityType == .note)
        #expect(note.soleConnectionLink == nil)
    }

    @Test func soleConnectionTokenBecomesLinkRow() {
        let parsed = ConceptMentionToken.parse("  @[Closing Loops](connection:\(uuid))  ")
        #expect(parsed.soleConnectionLink?.entityUUID == uuid)
        #expect(parsed.plainText.trimmingCharacters(in: .whitespaces) == "@Closing Loops")
    }

    @Test func displayTextStripsTokens() {
        let display = ConceptMentionToken.displayText(
            "- Linked because @[Closing Loops](connection:\(uuid)) narrows focus"
        )
        #expect(display == "- Linked because @Closing Loops narrows focus")
    }

    @Test func quickAddBuilderRoundTripsPickedMentions() {
        let mention = RichMention(
            entityUUID: uuid,
            entityID: nil,
            entityType: .connection,
            titleSnapshot: "Closing Loops"
        )
        let parsed = ConceptMentionToken.document(
            text: "Relates to @Closing Loops strongly",
            mentions: [mention]
        )
        #expect(parsed.plainText == "Relates to @Closing Loops strongly")
        #expect(parsed.mentions == [mention])
        #expect(ConceptMentionToken.mentions(in: parsed.document) == [mention])
    }

    @Test func mentionsCollectorWalksNestedBlocks() {
        let mention = RichMention(
            entityUUID: uuid,
            entityID: nil,
            entityType: .idea,
            titleSnapshot: "Nested"
        )
        let document = RichDocument(blocks: [
            RichBlock(
                kind: .paragraph,
                inlines: [.text("top")],
                children: [RichBlock(kind: .paragraph, inlines: [.mention(mention)])]
            )
        ])
        #expect(ConceptMentionToken.mentions(in: document) == [mention])
    }
}
