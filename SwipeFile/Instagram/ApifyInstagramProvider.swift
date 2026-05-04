// CosmoOS/SwipeFile/Instagram/ApifyInstagramProvider.swift
// Apify API implementation of InstagramDataProvider
// Uses Apify's Instagram scrapers via REST API

import Foundation

final class ApifyInstagramProvider: InstagramDataProvider, @unchecked Sendable {

    static let shared = ApifyInstagramProvider()

    private let baseURL = "https://api.apify.com/v2"
    private let session: URLSession

    // Actor IDs on Apify platform
    private let profileActorId = "apify~instagram-profile-scraper"
    private let postActorId = "apify~instagram-post-scraper"

    // Cost per post (approximate, based on Apify pricing)
    private let costPerPost: Double = 0.0005  // ~$0.50 per 1000 posts

    var isConfigured: Bool {
        guard let key = APIKeys.apify else { return false }
        return !key.isEmpty
    }

    private var apiToken: String? { APIKeys.apify }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Fetch Profile

    func fetchProfile(handle: String) async throws -> ImportedCreatorProfile {
        guard let token = apiToken else { throw ImportError.apiKeyMissing }

        let input: [String: Any] = [
            "usernames": [handle.replacingOccurrences(of: "@", with: "")],
            "resultsLimit": 1
        ]

        let results: [[String: Any]] = try await runActor(profileActorId, input: input, token: token)

        guard let profile = results.first else {
            throw ImportError.accountNotFound(handle)
        }

        let isPrivate = profile["private"] as? Bool ?? profile["isPrivate"] as? Bool ?? false
        if isPrivate {
            throw ImportError.privateAccount(handle)
        }

        return ImportedCreatorProfile(
            username: profile["username"] as? String ?? handle,
            fullName: profile["fullName"] as? String,
            biography: profile["biography"] as? String ?? profile["bio"] as? String,
            followerCount: profile["followersCount"] as? Int ?? profile["followedByCount"] as? Int ?? 0,
            followingCount: profile["followsCount"] as? Int ?? profile["followingCount"] as? Int ?? 0,
            postsCount: profile["postsCount"] as? Int ?? 0,
            profilePicUrl: profile["profilePicUrl"] as? String ?? profile["profilePicUrlHD"] as? String,
            isPrivate: isPrivate,
            isVerified: profile["verified"] as? Bool ?? profile["isVerified"] as? Bool ?? false
        )
    }

    // MARK: - Fetch Posts

    func fetchPosts(
        handle: String,
        maxPosts: Int,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [ImportedPost] {
        guard let token = apiToken else { throw ImportError.apiKeyMissing }

        let cleanHandle = handle.replacingOccurrences(of: "@", with: "")
        let input: [String: Any] = [
            "username": [cleanHandle],
            "resultsLimit": maxPosts
        ]

        let results: [[String: Any]] = try await runActor(
            postActorId,
            input: input,
            token: token,
            pollInterval: 3.0,
            onPoll: { itemCount in
                onProgress(itemCount, maxPosts)
            }
        )

        onProgress(results.count, results.count)

        return results.compactMap { parsePost($0, ownerUsername: cleanHandle) }
    }

    /// Fetch a single public Instagram post or reel by direct URL.
    /// Uses the same Apify post actor as creator import, but passes the post URL
    /// in the actor's `username` input, which the actor accepts for direct post scraping.
    func fetchPost(url: URL) async throws -> ImportedPost {
        guard let token = apiToken else { throw ImportError.apiKeyMissing }

        let input = Self.postActorInput(for: url)

        let results: [[String: Any]] = try await runActor(
            postActorId,
            input: input,
            token: token,
            pollInterval: 2.0
        )

        guard !results.isEmpty else {
            throw ImportError.apiError("Apify returned no items for post URL")
        }

        let shortcode = await InstagramExtractor.shared.extractShortcode(from: url)

        if let shortcode,
           let matching = results.first(where: {
               ($0["shortCode"] as? String ?? $0["shortcode"] as? String)?.caseInsensitiveCompare(shortcode) == .orderedSame
           }),
           let post = parsePost(matching, ownerUsername: shortcode) {
            return post
        }

        if let first = results.first,
           let post = parsePost(first, ownerUsername: shortcode ?? "") {
            return post
        }

        throw ImportError.decodingError("Could not parse Apify post result")
    }

    static func postActorInput(for url: URL) -> [String: Any] {
        [
            "username": [url.absoluteString],
            "resultsLimit": 1,
            // Direct post fallback needs child media for carousels. Apify's
            // basic payload can return only thumbnail/caption/imagesCount.
            "dataDetailLevel": "detailedData"
        ]
    }

    // MARK: - Cost Estimate

    func estimateCost(postCount: Int) -> ImportCostEstimate {
        let cost = Double(postCount) * costPerPost
        let duration = max(15, postCount / 5)  // ~5 posts/second, minimum 15s
        let warning: String? = postCount > 500
            ? "Large import — may take \(duration / 60)+ minutes and cost ~$\(String(format: "%.2f", cost))"
            : nil

        return ImportCostEstimate(
            postCount: postCount,
            estimatedCostUSD: cost,
            estimatedDurationSeconds: duration,
            warning: warning
        )
    }

    // MARK: - Actor Run + Polling

    /// Run an Apify actor and poll until completion, returning dataset items.
    private func runActor(
        _ actorId: String,
        input: [String: Any],
        token: String,
        pollInterval: TimeInterval = 2.0,
        onPoll: ((_ itemCount: Int) -> Void)? = nil
    ) async throws -> [[String: Any]] {
        // Start the actor run
        let runURL = URL(string: "\(baseURL)/acts/\(actorId)/runs?token=\(token)")!
        var request = URLRequest(url: runURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: input)

        let (runData, runResponse) = try await session.data(for: request)

        guard let httpResponse = runResponse as? HTTPURLResponse else {
            throw ImportError.apiError("Invalid response")
        }

        if httpResponse.statusCode == 429 {
            throw ImportError.rateLimited(retryAfterSeconds: 60)
        }

        guard httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            let body = String(data: runData, encoding: .utf8) ?? "Unknown error"
            throw ImportError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        guard let runJSON = try? JSONSerialization.jsonObject(with: runData) as? [String: Any],
              let runData2 = runJSON["data"] as? [String: Any],
              let runId = runData2["id"] as? String,
              let defaultDatasetId = runData2["defaultDatasetId"] as? String else {
            throw ImportError.decodingError("Could not parse actor run response")
        }

        // Poll for completion
        let statusURL = URL(string: "\(baseURL)/actor-runs/\(runId)?token=\(token)")!
        let datasetInfoURL = URL(string: "\(baseURL)/datasets/\(defaultDatasetId)?token=\(token)")!
        var pollCount = 0

        while true {
            try await Task.sleep(for: .seconds(pollInterval))
            pollCount += 1

            let (statusData, _) = try await session.data(for: URLRequest(url: statusURL))
            guard let statusJSON = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
                  let data = statusJSON["data"] as? [String: Any],
                  let status = data["status"] as? String else {
                continue
            }

            // Try run stats first for item count
            var reportedItemCount = 0
            if let stats = data["stats"] as? [String: Any],
               let itemCount = stats["datasetItemCount"] as? Int,
               itemCount > 0 {
                reportedItemCount = itemCount
            }

            // Fallback: poll dataset directly every 3rd cycle (more reliable for batch-write actors)
            if reportedItemCount == 0 && pollCount % 3 == 0 {
                if let (dsData, _) = try? await session.data(for: URLRequest(url: datasetInfoURL)),
                   let dsJSON = try? JSONSerialization.jsonObject(with: dsData) as? [String: Any],
                   let dsInfo = dsJSON["data"] as? [String: Any],
                   let dsItemCount = dsInfo["itemCount"] as? Int {
                    reportedItemCount = dsItemCount
                }
            }

            onPoll?(reportedItemCount)

            switch status {
            case "SUCCEEDED":
                return try await fetchDatasetItems(datasetId: defaultDatasetId, token: token)
            case "FAILED", "ABORTED", "TIMED-OUT":
                let message = (data["statusMessage"] as? String) ?? "Actor run \(status.lowercased())"
                throw ImportError.apiError(message)
            default:
                continue  // READY, RUNNING — keep polling
            }
        }
    }

    /// Fetch all items from an Apify dataset
    private func fetchDatasetItems(datasetId: String, token: String) async throws -> [[String: Any]] {
        let itemsURL = URL(string: "\(baseURL)/datasets/\(datasetId)/items?token=\(token)&format=json&clean=true")!
        let (data, response) = try await session.data(for: URLRequest(url: itemsURL))

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ImportError.apiError("Failed to fetch dataset items")
        }

        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ImportError.decodingError("Could not parse dataset items as JSON array")
        }

        return items
    }

    // MARK: - Parse Post

    func parsePost(_ json: [String: Any], ownerUsername: String) -> ImportedPost? {
        // Extract shortcode — required for dedup
        guard let shortcode = json["shortCode"] as? String ?? json["shortcode"] as? String else {
            return nil
        }

        let urlString = json["url"] as? String ?? "https://www.instagram.com/p/\(shortcode)/"
        guard let url = URL(string: urlString) else { return nil }

        // Content type
        let typeStr = json["type"] as? String ?? ""
        let contentType: InstagramContentType
        switch typeStr.lowercased() {
        case "video", "reel":
            contentType = .reel
        case "sidecar", "carousel":
            contentType = .carousel
        case "image":
            contentType = .image
        default:
            // Fallback: check if it has video play count
            if json["videoPlayCount"] as? Int != nil || json["videoViewCount"] as? Int != nil {
                contentType = .reel
            } else if json["childPosts"] as? [[String: Any]] != nil {
                contentType = .carousel
            } else {
                contentType = .image
            }
        }

        // Engagement
        let likes = json["likesCount"] as? Int ?? 0
        let comments = json["commentsCount"] as? Int ?? 0
        let views = json["videoPlayCount"] as? Int ?? json["videoViewCount"] as? Int
        let shares = json["sharesCount"] as? Int

        let engagement = InstagramEngagement(
            likesCount: max(likes, 0),  // -1 means hidden; normalize to 0
            commentsCount: comments,
            viewsCount: views,
            sharesCount: shares
        )

        // Timestamp
        let timestamp: Date
        if let ts = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: ts) ?? Date()
        } else if let epochStr = json["takenAtTimestamp"] as? Int {
            timestamp = Date(timeIntervalSince1970: TimeInterval(epochStr))
        } else {
            timestamp = Date()
        }

        // Caption & hashtags
        let caption = json["caption"] as? String
        let hashtags = json["hashtags"] as? [String]
            ?? extractHashtags(from: caption)

        // Media
        let thumbnailUrl = (json["displayUrl"] as? String ?? json["thumbnailUrl"] as? String)
            .flatMap { URL(string: $0) }
        let videoUrl = (json["videoUrl"] as? String)
            .flatMap { URL(string: $0) }

        // Carousel count + items
        let (carouselItems, carouselCount) = Self.parseCarouselItemsAndCount(from: json)

        // Location
        let locationName = json["locationName"] as? String
            ?? (json["location"] as? [String: Any])?["name"] as? String

        // Owner
        let owner = json["ownerUsername"] as? String ?? ownerUsername

        return ImportedPost(
            id: json["id"] as? String ?? shortcode,
            shortcode: shortcode,
            url: url,
            contentType: contentType,
            caption: caption,
            thumbnailUrl: thumbnailUrl,
            videoUrl: videoUrl,
            timestamp: timestamp,
            engagement: engagement,
            hashtags: hashtags,
            carouselMediaCount: carouselCount,
            carouselItems: carouselItems,
            locationName: locationName,
            ownerUsername: owner
        )
    }

    // MARK: - Helpers

    private func extractHashtags(from caption: String?) -> [String] {
        guard let caption else { return [] }
        let regex = try? NSRegularExpression(pattern: "#(\\w+)", options: [])
        let range = NSRange(caption.startIndex..., in: caption)
        let matches = regex?.matches(in: caption, range: range) ?? []
        return matches.compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: caption) else { return nil }
            return String(caption[tagRange])
        }
    }

    static func parseCarouselItemsAndCount(from json: [String: Any]) -> ([CarouselItem]?, Int?) {
        if let childPayloads = childPayloads(from: json), !childPayloads.isEmpty {
            let items = childPayloads.enumerated().compactMap { index, child in
                parseCarouselItem(from: child, index: index)
            }
            return (items.isEmpty ? nil : items, childPayloads.count)
        }

        if let images = firstStringArray(in: json, keys: [
            "images",
            "imageUrls",
            "imageURLS",
            "displayUrls",
            "displayURLS"
        ]), !images.isEmpty {
            let items = images.enumerated().compactMap { index, urlString -> CarouselItem? in
                guard let mediaURL = URL(string: urlString) else { return nil }
                return CarouselItem(
                    index: index,
                    mediaType: .image,
                    mediaURL: mediaURL,
                    thumbnailURL: mediaURL
                )
            }
            return (items.isEmpty ? nil : items, images.count)
        }

        if let imageDicts = firstDictionaryArray(in: json, keys: [
            "images",
            "imageUrls",
            "displayUrls"
        ]), !imageDicts.isEmpty {
            let items = imageDicts.enumerated().compactMap { index, child in
                parseCarouselItem(from: child, index: index)
            }
            return (items.isEmpty ? nil : items, imageDicts.count)
        }

        if let count = firstInt(in: json, keys: [
            "imagesCount",
            "imageCount",
            "carouselMediaCount",
            "carousel_media_count"
        ]), count > 0 {
            return (nil, count)
        }

        return (nil, nil)
    }

    private static func childPayloads(from json: [String: Any]) -> [[String: Any]]? {
        let directKeys = [
            "childPosts",
            "children",
            "carouselMedia",
            "carousel_media",
            "sidecarMedia",
            "sidecarChildren",
            "items"
        ]

        for key in directKeys {
            if let children = json[key] as? [[String: Any]], !children.isEmpty {
                return children
            }
            if let children = json[key] as? [String], !children.isEmpty {
                return children.map { ["displayUrl": $0] }
            }
        }

        let nestedKeys = [
            "carousel",
            "sidecar",
            "sidecarData",
            "edgeSidecarToChildren",
            "edge_sidecar_to_children"
        ]

        for key in nestedKeys {
            if let nested = json[key] as? [String: Any] {
                if let edges = nested["edges"] as? [[String: Any]] {
                    let nodes = edges.compactMap { $0["node"] as? [String: Any] }
                    if !nodes.isEmpty {
                        return nodes
                    }
                }

                if let children = childPayloads(from: nested), !children.isEmpty {
                    return children
                }
            }
        }

        if let edgeSidecar = json["edge_sidecar_to_children"] as? [String: Any],
           let edges = edgeSidecar["edges"] as? [[String: Any]] {
            let nodes = edges.compactMap { $0["node"] as? [String: Any] }
            if !nodes.isEmpty {
                return nodes
            }
        }

        return nil
    }

    private static func parseCarouselItem(from child: [String: Any], index: Int) -> CarouselItem? {
        let payload: [String: Any]
        if let node = child["node"] as? [String: Any] {
            payload = node
        } else {
            payload = child
        }

        let childType = (payload["type"] as? String ?? payload["mediaType"] as? String ?? "").lowercased()
        let isVideoFlag = payload["isVideo"] as? Bool ?? payload["is_video"] as? Bool ?? false
        let isVideo = isVideoFlag || childType == "video" || childType == "reel"
        let mediaType: CarouselMediaType = isVideo ? .video : .image

        let displayURLString = firstString(in: payload, keys: [
            "displayUrl",
            "display_url",
            "imageUrl",
            "image_url",
            "mediaUrl",
            "media_url",
            "thumbnailUrl",
            "thumbnail_url",
            "url",
            "src"
        ])
        let videoURLString = firstString(in: payload, keys: [
            "videoUrl",
            "video_url",
            "videoUrlDownload",
            "video_url_download"
        ])

        let mediaURLString = isVideo ? (videoURLString ?? displayURLString) : (displayURLString ?? videoURLString)
        guard let mediaURLString, let mediaURL = URL(string: mediaURLString) else {
            return nil
        }

        let thumbnailURL = displayURLString.flatMap(URL.init(string:))
        let duration = payload["videoDuration"] as? TimeInterval ?? payload["video_duration"] as? TimeInterval

        return CarouselItem(
            index: index,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbnailURL: thumbnailURL,
            duration: duration
        )
    }

    private static func firstString(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstStringArray(in json: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let values = json[key] as? [String], !values.isEmpty {
                return values
            }
        }
        return nil
    }

    private static func firstDictionaryArray(in json: [String: Any], keys: [String]) -> [[String: Any]]? {
        for key in keys {
            if let values = json[key] as? [[String: Any]], !values.isEmpty {
                return values
            }
        }
        return nil
    }

    private static func firstInt(in json: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = json[key] as? Int {
                return value
            }
            if let value = json[key] as? Double {
                return Int(value)
            }
            if let value = json[key] as? String, let intValue = Int(value) {
                return intValue
            }
        }
        return nil
    }
}
