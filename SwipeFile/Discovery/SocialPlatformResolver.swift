import Foundation

enum SocialPlatformResolver {
    static func resolve(input: String) -> SocialPlatformIdentity? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let identity = resolvePlatformPrefixedHandle(trimmed) {
            return identity
        }

        guard let url = URL(string: trimmed),
              let host = url.host(percentEncoded: false)?.lowercased()
        else {
            return nil
        }

        return resolveURL(url, host: host)
    }

    private static func resolvePlatformPrefixedHandle(_ input: String) -> SocialPlatformIdentity? {
        let parts = input.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2,
              let platform = platform(named: String(parts[0])),
              let handle = normalizedHandle(String(parts[1]))
        else {
            return nil
        }

        return SocialPlatformIdentity(platform: platform, handle: handle, profileURL: nil)
    }

    private static func resolveURL(_ url: URL, host: String) -> SocialPlatformIdentity? {
        if host == "instagram.com" || host == "www.instagram.com" {
            return identity(
                from: url,
                platform: .instagram,
                ignoredFirstSegments: [
                    "p", "reel", "reels", "tv", "stories", "explore", "accounts",
                    "direct", "about", "privacy", "terms", "developer", "web"
                ]
            )
        }

        if host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" {
            return youtubeIdentity(from: url)
        }

        if host == "x.com" || host == "www.x.com" || host == "twitter.com" || host == "www.twitter.com" {
            return identity(from: url, platform: .x, ignoredFirstSegments: ["i", "home", "explore", "notifications", "messages", "search"])
        }

        if host == "linkedin.com" || host == "www.linkedin.com" {
            return linkedinIdentity(from: url)
        }

        if host == "substack.com" || host.hasSuffix(".substack.com") {
            return substackIdentity(from: url, host: host)
        }

        if host == "tiktok.com" || host == "www.tiktok.com" {
            return identity(from: url, platform: .tiktok)
        }

        return nil
    }

    private static func identity(
        from url: URL,
        platform: SocialPlatform,
        ignoredFirstSegments: Set<String> = []
    ) -> SocialPlatformIdentity? {
        guard let firstSegment = firstPathSegment(from: url),
              !ignoredFirstSegments.contains(firstSegment.lowercased()),
              let handle = normalizedHandle(firstSegment)
        else {
            return nil
        }

        return SocialPlatformIdentity(platform: platform, handle: handle, profileURL: url)
    }

    private static func youtubeIdentity(from url: URL) -> SocialPlatformIdentity? {
        let segments = pathSegments(from: url)
        guard let first = segments.first else { return nil }

        if first.hasPrefix("@"), let handle = normalizedHandle(first) {
            return SocialPlatformIdentity(platform: .youtube, handle: handle, profileURL: url)
        }

        if ["channel", "c", "user"].contains(first.lowercased()), segments.count > 1,
           let handle = normalizedHandle(segments[1]) {
            return SocialPlatformIdentity(platform: .youtube, handle: handle, profileURL: url)
        }

        return nil
    }

    private static func linkedinIdentity(from url: URL) -> SocialPlatformIdentity? {
        let segments = pathSegments(from: url)
        guard segments.count > 1,
              ["in", "company", "school"].contains(segments[0].lowercased()),
              let handle = normalizedHandle(segments[1])
        else {
            return nil
        }

        return SocialPlatformIdentity(platform: .linkedin, handle: handle, profileURL: url)
    }

    private static func substackIdentity(from url: URL, host: String) -> SocialPlatformIdentity? {
        if host.hasSuffix(".substack.com") {
            let subdomain = host.replacingOccurrences(of: ".substack.com", with: "")
            guard let handle = normalizedHandle(subdomain), handle != "www" else { return nil }
            return SocialPlatformIdentity(platform: .substack, handle: handle, profileURL: url)
        }

        guard let firstSegment = firstPathSegment(from: url),
              let handle = normalizedHandle(firstSegment)
        else {
            return nil
        }

        return SocialPlatformIdentity(platform: .substack, handle: handle, profileURL: url)
    }

    private static func platform(named rawValue: String) -> SocialPlatform? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "instagram", "ig":
            return .instagram
        case "youtube", "yt":
            return .youtube
        case "x", "twitter":
            return .x
        case "linkedin", "li":
            return .linkedin
        case "substack":
            return .substack
        case "tiktok":
            return .tiktok
        default:
            return nil
        }
    }

    private static func firstPathSegment(from url: URL) -> String? {
        pathSegments(from: url).first
    }

    private static func pathSegments(from url: URL) -> [String] {
        url.path(percentEncoded: false)
            .split(separator: "/")
            .map(String.init)
    }

    private static func normalizedHandle(_ rawHandle: String) -> String? {
        let trimmed = rawHandle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@/"))

        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
