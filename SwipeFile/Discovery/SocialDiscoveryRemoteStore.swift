import Foundation

struct SocialDiscoveryRemoteCreator: Codable, Equatable, Identifiable, Sendable {
    let uuid: String
    let platform: SocialPlatform
    let handle: String
    let displayName: String?
    let bio: String?
    let avatarURL: URL?
    let profileURL: URL?
    let followerCount: Int?

    enum CodingKeys: String, CodingKey {
        case uuid
        case platform
        case handle
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case profileURL = "profile_url"
        case followerCount = "follower_count"
    }

    var id: String { uuid }
}

final class SocialDiscoveryRemoteStore: Sendable {
    enum RemoteStoreError: LocalizedError {
        case missingConfiguration
        case invalidResponse(Int, String?)

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Discovery API is not configured."
            case let .invalidResponse(status, message):
                if let message, !message.isEmpty {
                    return "Discovery API returned HTTP \(status): \(message)"
                }
                return "Discovery API returned HTTP \(status)."
            }
        }
    }

    private struct FeedResponse: Decodable {
        let posts: [PostRow]
    }

    private struct CreatorsResponse: Decodable {
        let creators: [SocialDiscoveryRemoteCreator]
    }

    private struct AddSourceResponse: Decodable {
        let source: SourceRow
    }

    private struct SourceRow: Decodable {
        let uuid: String
    }

    struct PostRow: Decodable {
        let uuid: String
        let platform: SocialPlatform
        let platformPostID: String
        let creatorUUID: String?
        let canonicalURL: URL
        let title: String?
        let caption: String?
        let transcript: String?
        let language: String?
        let postedAt: Date?
        let mediaType: String
        let mediaURLs: [MediaRow]
        let thumbnailURL: URL?
        let durationSeconds: Int?
        let viewCount: Int?
        let likeCount: Int?
        let commentCount: Int?
        let repostCount: Int?
        let shareCount: Int?
        let engagementRate: Double?
        let outlierScore: Double?
        let outlierGrade: String?
        let savedAtomUUID: String?

        enum CodingKeys: String, CodingKey {
            case uuid
            case platform
            case platformPostID = "platform_post_id"
            case creatorUUID = "creator_uuid"
            case canonicalURL = "canonical_url"
            case title
            case caption
            case transcript
            case language
            case postedAt = "posted_at"
            case mediaType = "media_type"
            case mediaURLs = "media_urls"
            case thumbnailURL = "thumbnail_url"
            case durationSeconds = "duration_seconds"
            case viewCount = "view_count"
            case likeCount = "like_count"
            case commentCount = "comment_count"
            case repostCount = "repost_count"
            case shareCount = "share_count"
            case engagementRate = "engagement_rate"
            case outlierScore = "outlier_score"
            case outlierGrade = "outlier_grade"
            case savedAtomUUID = "saved_atom_uuid"
        }
    }

    struct MediaRow: Decodable {
        let kind: String
        let url: URL
        let width: Int?
        let height: Int?
        let durationSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case kind
            case url
            case width
            case height
            case durationSeconds
        }
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.discovery.date(from: value)
                ?? ISO8601DateFormatter.discoveryNoFractionalSeconds.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
        self.decoder = decoder
    }

    var isConfigured: Bool {
        APIKeys.hasDiscoveryAPI
    }

    func fetchPosts(query: SocialDiscoveryQuery) async throws -> [SocialPostSnapshot] {
        guard isConfigured else { throw RemoteStoreError.missingConfiguration }
        async let creators = fetchCreators()
        async let posts = fetchPostRows(query: query)
        let creatorRows = try await creators
        let postRows = try await posts
        let creatorMap = Dictionary(uniqueKeysWithValues: creatorRows.map { ($0.uuid, $0) })
        return postRows.map { $0.snapshot(creator: $0.creatorUUID.flatMap { creatorMap[$0] }) }
    }

    func fetchCreators() async throws -> [SocialDiscoveryRemoteCreator] {
        guard isConfigured else { throw RemoteStoreError.missingConfiguration }
        let response: CreatorsResponse = try await request(path: "/api/discovery/creators", queryItems: [
            URLQueryItem(name: "limit", value: "500")
        ])
        return response.creators
    }

    @discardableResult
    func addCreator(identity: SocialPlatformIdentity, nicheTags: [String] = []) async throws -> String {
        guard isConfigured else { throw RemoteStoreError.missingConfiguration }
        var request = try makeRequest(path: "/api/discovery/sources")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AddSourceRequest(
            kind: "tracked_creator",
            platform: identity.platform.rawValue,
            label: identity.handle,
            query: identity.handle,
            profileURL: identity.profileURL?.absoluteString,
            nicheTags: nicheTags
        ))
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        let created = try decoder.decode(AddSourceResponse.self, from: data)
        return created.source.uuid
    }

    func refreshDue(limit: Int = 25) async throws {
        guard isConfigured else { throw RemoteStoreError.missingConfiguration }
        var request = try makeRequest(path: "/api/discovery/refresh-due")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        request.httpBody = try JSONEncoder().encode(RefreshDueRequest(limit: limit))
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    func refreshSource(sourceID: String) async throws {
        guard isConfigured else { throw RemoteStoreError.missingConfiguration }
        var request = try makeRequest(path: "/api/discovery/sources/\(sourceID)/refresh")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    func savePost(postID: String, boardID: String?) async throws {
        guard isConfigured else { throw RemoteStoreError.missingConfiguration }
        var request = try makeRequest(path: "/api/discovery/posts/\(postID)/save")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SavePostRequest(boardID: boardID))
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    private func fetchPostRows(query: SocialDiscoveryQuery) async throws -> [PostRow] {
        let response: FeedResponse = try await request(path: "/api/discovery/feed", queryItems: query.remoteQueryItems)
        return response.posts
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var request = try makeRequest(path: path, queryItems: queryItems)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard let base = APIKeys.discoveryApiBaseURL,
              let key = APIKeys.discoveryApiKey,
              let normalizedBase = Self.normalizedDiscoveryAPIBaseURL(base),
              var components = URLComponents(string: normalizedBase)
        else {
            throw RemoteStoreError.missingConfiguration
        }

        components.path += path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw RemoteStoreError.missingConfiguration }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let apifyKey = APIKeys.apify?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apifyKey.isEmpty {
            request.setValue(apifyKey, forHTTPHeaderField: "X-Apify-Api-Key")
        }
        request.timeoutInterval = 30
        return request
    }

    static func normalizedDiscoveryAPIBaseURL(_ rawBaseURL: String) -> String? {
        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let absoluteBase = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: absoluteBase),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false
        else {
            return nil
        }

        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.query = nil
        components.fragment = nil
        return components.string
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteStoreError.invalidResponse(http.statusCode, message(from: data))
        }
    }

    private func message(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? String { return error }
            if let message = object["message"] as? String { return message }
        }

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AddSourceRequest: Encodable {
    let kind: String
    let platform: String
    let label: String
    let query: String
    let profileURL: String?
    let nicheTags: [String]

    enum CodingKeys: String, CodingKey {
        case kind
        case platform
        case label
        case query
        case profileURL = "profileUrl"
        case nicheTags
    }
}

private struct SavePostRequest: Encodable {
    let boardID: String?

    enum CodingKeys: String, CodingKey {
        case boardID = "boardId"
    }
}

private struct RefreshDueRequest: Encodable {
    let limit: Int
}

private extension SocialDiscoveryQuery {
    var remoteQueryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !platforms.isEmpty {
            items.append(URLQueryItem(
                name: "platforms",
                value: platforms.map(\.rawValue).sorted().joined(separator: ",")
            ))
        }
        if let minimumOutlierMultiplier {
            items.append(URLQueryItem(name: "minOutlier", value: String(minimumOutlierMultiplier)))
        }
        items.append(URLQueryItem(name: "window", value: postedWindow.remoteValue))
        let searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            items.append(URLQueryItem(name: "q", value: searchText))
        }
        items.append(URLQueryItem(name: "limit", value: "200"))
        return items
    }
}

private extension SocialPostedWindow {
    var remoteValue: String {
        switch self {
        case .lastWeek: return "week"
        case .lastMonth: return "month"
        case .lastThreeMonths: return "3months"
        case .lastYear: return "year"
        case .allTime: return "all"
        }
    }
}

private extension SocialDiscoveryRemoteStore.PostRow {
    func snapshot(creator: SocialDiscoveryRemoteCreator?) -> SocialPostSnapshot {
        let fallbackHandle = creator?.handle ?? "unknown"
        let author = SocialCreatorSnapshot(
            platformID: creator?.uuid ?? creatorUUID ?? fallbackHandle,
            handle: fallbackHandle,
            displayName: creator?.displayName ?? fallbackHandle,
            avatarURL: creator?.avatarURL,
            followerCount: creator?.followerCount
        )
        let media = mediaAssets
        let derived = SocialDerivedMetrics(
            outlierMultiplier: outlierScore,
            outlierGrade: mappedGrade,
            engagementRate: engagementRate
        )

        return SocialPostSnapshot(
            id: uuid,
            platform: platform,
            provider: "cloud-discovery",
            providerPostID: platformPostID,
            canonicalURL: canonicalURL,
            title: title,
            body: caption,
            media: media,
            author: author,
            publishedAt: postedAt,
            detectedLanguage: language,
            format: mappedFormat,
            metrics: SocialEngagementMetrics(
                views: viewCount,
                likes: likeCount,
                comments: commentCount,
                shares: shareCount,
                reposts: repostCount
            ),
            derived: derived,
            transcriptState: transcript.map(SocialTranscriptState.available) ?? .none,
            saveState: savedAtomUUID == nil ? .unsaved : .saved,
            rawProviderPayload: nil
        )
    }

    private var mediaAssets: [SocialMediaAsset] {
        var assets = mediaURLs.compactMap(\.asset)
        if assets.isEmpty, let thumbnailURL {
            assets.append(SocialMediaAsset(kind: .thumbnail, url: thumbnailURL))
        }
        return assets
    }

    private var mappedFormat: SocialContentFormat {
        switch mediaType {
        case "short_video": return .shortVideo
        case "video": return durationSeconds.map { $0 <= 90 ? .shortVideo : .longVideo } ?? .longVideo
        case "image": return .image
        case "carousel": return .carousel
        case "article": return .newsletter
        case "text": return .text
        default: return .unknown
        }
    }

    private var mappedGrade: SocialOutlierGrade {
        switch outlierGrade?.lowercased() {
        case "s": return .s
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "baseline": return .baseline
        default: return .insufficientData
        }
    }
}

private extension SocialDiscoveryRemoteStore.MediaRow {
    var asset: SocialMediaAsset? {
        let mappedKind: SocialMediaAsset.Kind
        switch kind {
        case "video": mappedKind = .video
        case "thumbnail": mappedKind = .thumbnail
        case "document": mappedKind = .document
        default: mappedKind = .image
        }
        return SocialMediaAsset(kind: mappedKind, url: url, width: width, height: height, duration: durationSeconds)
    }
}

private extension ISO8601DateFormatter {
    static let discovery: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let discoveryNoFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
