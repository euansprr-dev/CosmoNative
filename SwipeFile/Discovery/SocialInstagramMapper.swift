import Foundation

enum SocialInstagramMapper {
    static func snapshot(
        post: ImportedPost,
        profile: ImportedCreatorProfile,
        outlier: SocialDerivedMetrics = .empty,
        transcriptState: SocialTranscriptState = .none,
        saveState: SocialSaveState = .unsaved
    ) -> SocialPostSnapshot {
        SocialPostSnapshot(
            id: "instagram:\(post.id)",
            platform: .instagram,
            provider: "instagram",
            providerPostID: post.id,
            canonicalURL: post.url,
            title: nil,
            body: post.caption,
            media: mediaAssets(for: post),
            author: SocialCreatorSnapshot(
                platformID: profile.username,
                handle: profile.username,
                displayName: profile.fullName?.nilIfBlank ?? profile.username,
                avatarURL: profile.profilePicUrl.flatMap(URL.init(string:)),
                followerCount: profile.followerCount
            ),
            publishedAt: post.timestamp,
            detectedLanguage: nil,
            format: contentFormat(for: post.contentType),
            metrics: SocialEngagementMetrics(
                views: post.engagement.viewsCount,
                likes: post.engagement.likesCount,
                comments: post.engagement.commentsCount,
                shares: post.engagement.sharesCount,
                saves: nil,
                reposts: nil,
                impressions: post.engagement.viewsCount
            ),
            derived: outlier,
            transcriptState: transcriptState,
            saveState: saveState,
            rawProviderPayload: nil
        )
    }

    static func contentFormat(for contentType: InstagramContentType) -> SocialContentFormat {
        switch contentType {
        case .reel, .story:
            return .shortVideo
        case .videoPost:
            return .longVideo
        case .carousel:
            return .carousel
        case .image:
            return .image
        }
    }

    private static func mediaAssets(for post: ImportedPost) -> [SocialMediaAsset] {
        var assets: [SocialMediaAsset] = []

        if let thumbnailUrl = post.thumbnailUrl {
            assets.append(SocialMediaAsset(kind: .thumbnail, url: thumbnailUrl))
        }

        if let videoUrl = post.videoUrl {
            assets.append(SocialMediaAsset(kind: .video, url: videoUrl))
        }

        if let carouselItems = post.carouselItems {
            assets.append(contentsOf: carouselItems.map { item in
                SocialMediaAsset(kind: mediaKind(for: item.mediaType), url: item.mediaURL, duration: item.duration)
            })
        }

        return assets
    }

    private static func mediaKind(for mediaType: CarouselMediaType) -> SocialMediaAsset.Kind {
        switch mediaType {
        case .image:
            return .image
        case .video:
            return .video
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
