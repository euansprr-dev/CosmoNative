import XCTest
@testable import CosmoOS

final class SocialInstagramMapperTests: XCTestCase {
    func testMapsImportedInstagramPostIntoProviderNeutralSnapshot() {
        let profile = ImportedCreatorProfile(
            username: "jun_yuh",
            fullName: "Jun Yuh",
            biography: "Personal branding and content strategy",
            followerCount: 183_000,
            followingCount: 412,
            postsCount: 1_240,
            profilePicUrl: "https://example.com/avatar.jpg",
            isPrivate: false,
            isVerified: true
        )

        let post = ImportedPost(
            id: "ig-123",
            shortcode: "CxYz123AbC",
            url: URL(string: "https://www.instagram.com/reel/CxYz123AbC/")!,
            contentType: .reel,
            caption: "everything in your life is a reflection of a decision you make",
            thumbnailUrl: URL(string: "https://example.com/thumb.jpg"),
            videoUrl: URL(string: "https://example.com/video.mp4"),
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            engagement: InstagramEngagement(likesCount: 181_000, commentsCount: 287, viewsCount: 6_100_000, sharesCount: 9_200),
            hashtags: ["mindset"],
            carouselMediaCount: nil,
            carouselItems: nil,
            locationName: nil,
            ownerUsername: "jun_yuh"
        )

        let snapshot = SocialInstagramMapper.snapshot(
            post: post,
            profile: profile,
            outlier: .init(outlierMultiplier: 16, outlierGrade: .s, engagementRate: 0.0297),
            transcriptState: .none,
            saveState: .unsaved
        )

        XCTAssertEqual(snapshot.id, "instagram:ig-123")
        XCTAssertEqual(snapshot.platform, .instagram)
        XCTAssertEqual(snapshot.provider, "instagram")
        XCTAssertEqual(snapshot.providerPostID, "ig-123")
        XCTAssertEqual(snapshot.body, post.caption)
        XCTAssertEqual(snapshot.author.handle, "jun_yuh")
        XCTAssertEqual(snapshot.author.displayName, "Jun Yuh")
        XCTAssertEqual(snapshot.author.followerCount, 183_000)
        XCTAssertEqual(snapshot.format, .shortVideo)
        XCTAssertEqual(snapshot.metrics.views, 6_100_000)
        XCTAssertEqual(snapshot.metrics.likes, 181_000)
        XCTAssertEqual(snapshot.metrics.comments, 287)
        XCTAssertEqual(snapshot.metrics.shares, 9_200)
        XCTAssertEqual(snapshot.derived.outlierMultiplier, 16)
        XCTAssertEqual(snapshot.media.map(\.kind), [.thumbnail, .video])
    }

    func testMapsInstagramContentFormatsWithoutLeakingInstagramTypesIntoUI() {
        XCTAssertEqual(SocialInstagramMapper.contentFormat(for: .reel), .shortVideo)
        XCTAssertEqual(SocialInstagramMapper.contentFormat(for: .videoPost), .longVideo)
        XCTAssertEqual(SocialInstagramMapper.contentFormat(for: .carousel), .carousel)
        XCTAssertEqual(SocialInstagramMapper.contentFormat(for: .image), .image)
        XCTAssertEqual(SocialInstagramMapper.contentFormat(for: .story), .shortVideo)
    }
}
