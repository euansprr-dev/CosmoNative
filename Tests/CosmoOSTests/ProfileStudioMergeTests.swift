// Tests/CosmoOSTests/ProfileStudioMergeTests.swift
// The Profile Studio save contract: studio-owned keys merge over existing
// metadata at the key level — keys owned by other writers survive every
// save, and cleared fields persist as real deletions (explicit nulls).

import XCTest
@testable import CosmoOS

final class ProfileStudioMergeTests: XCTestCase {

    private func makeOverlay(
        name: String = "Test Voice",
        handle: String = "@voice",
        documents: [ProfileDocument] = [],
        niche: String = "",
        signaturePhrases: [String] = []
    ) -> ProfileStudioOverlay {
        ProfileStudioOverlay(
            clientId: "client-1",
            clientName: name,
            activeStatus: true,
            handle: handle,
            platforms: [.instagram],
            primaryPlatform: .instagram,
            documents: documents,
            targetAudience: "",
            niche: niche,
            uniqueAngle: "",
            signaturePhrases: signaturePhrases,
            coreBeliefs: [],
            notes: "",
            brandStory: "",
            voiceNotes: "",
            topPerformingPosts: []
        )
    }

    private func metadataDict(of atom: Atom) throws -> [String: Any] {
        let data = try XCTUnwrap(atom.metadata?.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Key-level merge

    func testMergePreservesKeysOwnedByOtherWriters() throws {
        var atom = Atom.new(type: .clientProfile, title: "Existing", body: nil)
        atom.metadata = """
        {"clientName":"Existing","intelligenceModel":{"generatedAt":773452800},\
        "extractedVoicePatterns":{"tone":"warm"},"totalReach":12345,\
        "someFutureKey":"must-survive"}
        """

        let merged = atom.mergingMetadataKeys(makeOverlay(name: "Renamed"))
        let dict = try metadataDict(of: merged)

        XCTAssertEqual(dict["clientName"] as? String, "Renamed")
        XCTAssertNotNil(dict["intelligenceModel"], "intelligence model must survive a studio save")
        XCTAssertNotNil(dict["extractedVoicePatterns"], "voice patterns must survive a studio save")
        XCTAssertEqual(dict["totalReach"] as? Int, 12345)
        XCTAssertEqual(dict["someFutureKey"] as? String, "must-survive")
    }

    func testClearedFieldsPersistAsDeletions() throws {
        var atom = Atom.new(type: .clientProfile, title: "Existing", body: nil)
        atom.metadata = #"{"clientName":"Existing","handle":"@old","niche":"Old niche"}"#

        // Studio cleared handle and niche → explicit nulls in the overlay.
        let merged = atom.mergingMetadataKeys(makeOverlay(handle: "", niche: ""))
        let decoded = try XCTUnwrap(merged.metadataValue(as: ClientProfileMetadata.self))

        XCTAssertNil(decoded.handle, "a cleared handle must not resurrect the old value")
        XCTAssertNil(decoded.niche, "a cleared niche must not resurrect the old value")
    }

    func testDocumentsAndContextRoundTrip() throws {
        var atom = Atom.new(type: .clientProfile, title: "Voice", body: nil)
        atom.metadata = "{}"

        let doc = ProfileDocument(
            category: .voiceGuide,
            title: "From Library",
            content: "Reference text",
            sourceAtomUUID: "lib-atom-1"
        )
        let merged = atom.mergingMetadataKeys(
            makeOverlay(documents: [doc], signaturePhrases: ["systems beat hustle"])
        )
        let decoded = try XCTUnwrap(merged.metadataValue(as: ClientProfileMetadata.self))

        XCTAssertEqual(decoded.documents?.count, 1)
        XCTAssertEqual(decoded.documents?.first?.sourceAtomUUID, "lib-atom-1")
        XCTAssertEqual(decoded.signaturePhrases, ["systems beat hustle"])
    }

    // MARK: - Legacy decoding

    func testLegacyTopPerformerCategoryDecodesAsReel() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","category":"topPerformer","title":"Old doc","content":"text"}"#
        let doc = try JSONDecoder().decode(ProfileDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.category, .reel)
    }

    func testMetadataWithoutDocumentsStillDecodes() throws {
        var atom = Atom.new(type: .clientProfile, title: "Legacy", body: nil)
        atom.metadata = """
        {"clientName":"Legacy","brandStory":"origin story","voiceNotes":"tone notes",\
        "topPerformingPosts":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF",\
        "transcript":"a post","platform":"reel","likes":10,"shares":2,"leads":0,\
        "views":100,"datePosted":""}]}
        """
        let decoded = try XCTUnwrap(atom.metadataValue(as: ClientProfileMetadata.self))
        XCTAssertEqual(decoded.brandStory, "origin story")
        XCTAssertEqual(decoded.topPerformingPosts?.count, 1)
        XCTAssertNil(decoded.documents)
    }
}
