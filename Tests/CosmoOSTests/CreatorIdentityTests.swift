import XCTest
@testable import CosmoOS

/// The one creator identity: every path that names a creator must agree.
final class CreatorIdentityTests: XCTestCase {

    func testKeyNormalizesEverySpelling() {
        XCTAssertEqual(CreatorIdentity.key("@JoshVillareal"), "joshvillareal")
        XCTAssertEqual(CreatorIdentity.key("  joshvillareal/ "), "joshvillareal")
        XCTAssertEqual(CreatorIdentity.key("https://www.instagram.com/joshvillareal/"), "joshvillareal")
        XCTAssertEqual(CreatorIdentity.key("Ben Allgeyer | Real Estate Investor"), "ben_allgeyer")
        XCTAssertEqual(CreatorIdentity.key("youtube.com/@aliabdaal"), "aliabdaal")
        XCTAssertEqual(CreatorIdentity.key("@josh.villareal"), "josh.villareal")
    }

    func testKeyRefusesEmptyAndNumericIds() {
        XCTAssertNil(CreatorIdentity.key(nil))
        XCTAssertNil(CreatorIdentity.key(""))
        XCTAssertNil(CreatorIdentity.key("@"))
        XCTAssertNil(CreatorIdentity.key("1234567890"), "a leaked numeric Instagram id is not a handle")
    }

    func testLooseKeyIsSeparatorBlind() {
        XCTAssertEqual(CreatorIdentity.looseKey("josh_villareal"), CreatorIdentity.looseKey("josh.villareal"))
        XCTAssertEqual(CreatorIdentity.looseKey("josh-villareal"), "joshvillareal")
    }

    func testPlatformComesFromTheSourceNeverTheCaptureChannel() {
        XCTAssertEqual(CreatorIdentity.platform(fromSourceKey: "instagram_reel"), .instagram)
        XCTAssertEqual(CreatorIdentity.platform(fromSourceKey: "youtube_short"), .youtube)
        XCTAssertEqual(CreatorIdentity.platform(fromSourceKey: "x_post"), .x)
        XCTAssertEqual(CreatorIdentity.platform(fromSourceKey: "threads"), .threads)
        XCTAssertNil(CreatorIdentity.platform(fromSourceKey: "clipboard"))
        XCTAssertNil(CreatorIdentity.platform(fromSourceKey: "capture"))
        XCTAssertNil(CreatorIdentity.platform(fromCreatorPlatform: "creator_import"))
        XCTAssertNil(CreatorIdentity.platform(fromCreatorPlatform: "other"))
        XCTAssertEqual(CreatorIdentity.platform(fromCreatorPlatform: "instagram"), .instagram)
        XCTAssertEqual(CreatorIdentity.platform(fromURL: "https://www.tiktok.com/@someone/video/1"), .tiktok)
    }

    func testMatchPrefersSamePlatformThenAnyThenLooseOnlyWhenSafe() {
        let ig = creator(handle: "@joshvillareal", platform: "instagram", followers: 48_000)
        let yt = creator(handle: "@joshvillareal", platform: "youtube")
        let clip = creator(handle: "@Josh_Villareal", platform: "clipboard")

        XCTAssertEqual(CreatorIdentity.match(key: "joshvillareal", platform: .youtube, derivedFromName: false, in: [ig, yt])?.uuid, yt.uuid)
        XCTAssertEqual(CreatorIdentity.match(key: "joshvillareal", platform: .tiktok, derivedFromName: false, in: [ig, yt])?.uuid, ig.uuid,
                       "an exact handle on another platform beats minting a twin")
        XCTAssertEqual(CreatorIdentity.match(key: "josh_villareal", platform: .instagram, derivedFromName: true, in: [ig])?.uuid, ig.uuid,
                       "a name-spelled handle finds the real username")
        XCTAssertEqual(CreatorIdentity.match(key: "joshvillareal", platform: .instagram, derivedFromName: false, in: [clip])?.uuid, clip.uuid,
                       "a real username adopts the never-imported twin the classifier spelled")
        XCTAssertNil(CreatorIdentity.match(key: "j.smith", platform: .instagram, derivedFromName: false, in: [creator(handle: "@jsmith", platform: "instagram", followers: 10)]),
                     "two real, imported usernames that differ by a dot stay two people")
    }

    @MainActor
    func testTwinGroupsFoldTheNameSpelledHandleIntoTheImportedCreator() {
        let imported = creator(handle: "@joshvillareal", platform: "instagram", followers: 48_000)
        let spelled = creator(handle: "@josh_villareal", platform: "clipboard")
        let dupe = creator(handle: "@JoshVillareal", platform: "creator_import")
        let other = creator(handle: "@someoneelse", platform: "instagram")

        let groups = CreatorDirectory.twinGroups(in: [imported, spelled, dupe, other])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(\.uuid)), [imported.uuid, spelled.uuid, dupe.uuid])
    }

    // MARK: - Fixtures

    private func creator(handle: String, platform: String, followers: Int? = nil) -> Atom {
        let metadata = CreatorMetadata(handle: handle, platform: platform, followerCount: followers, swipeCount: 0, isActive: true)
        let json = String(data: try! JSONEncoder().encode(metadata), encoding: .utf8)
        return Atom.new(type: .creator, title: handle, body: nil, metadata: json)
    }
}
