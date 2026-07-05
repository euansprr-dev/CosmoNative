// CosmoOS/AI/DeepScoutProviders.swift

import Foundation

enum DeepScoutProviders {
    static func fetchOpenLibrary(
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let url = searchURL(base: "https://openlibrary.org/search.json", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "8")
        ]) else {
            return (InquiryProviderStatus(provider: .openLibrary, state: .failed, message: "Invalid query"), [])
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let docs = object?["docs"] as? [[String: Any]] ?? []
            let candidates = docs.compactMap {
                openLibraryCandidate(from: $0, query: query, lane: lane, intent: intent, profile: profile)
            }
            return (InquiryProviderStatus(provider: .openLibrary, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .openLibrary, state: .failed, message: error.localizedDescription), [])
        }
    }

    static func fetchGoogleBooks(
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let url = searchURL(base: "https://www.googleapis.com/books/v1/volumes", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "8"),
            URLQueryItem(name: "printType", value: "books")
        ]) else {
            return (InquiryProviderStatus(provider: .googleBooks, state: .failed, message: "Invalid query"), [])
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let items = object?["items"] as? [[String: Any]] ?? []
            let candidates = items.compactMap {
                googleBooksCandidate(from: $0, lane: lane, intent: intent, profile: profile)
            }
            return (InquiryProviderStatus(provider: .googleBooks, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .googleBooks, state: .failed, message: error.localizedDescription), [])
        }
    }

    static func fetchInternetArchive(
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        // Title-scoped: full-text search surfaces archival noise (catalog IDs,
        // declassified document dumps) whose bodies merely mention the terms.
        let archiveQuery = "title:(\(query)) AND mediatype:(texts)"
        guard let url = searchURL(base: "https://archive.org/advancedsearch.php", queryItems: [
            URLQueryItem(name: "q", value: archiveQuery),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "fl[]", value: "date"),
            URLQueryItem(name: "fl[]", value: "description"),
            URLQueryItem(name: "rows", value: "8"),
            URLQueryItem(name: "output", value: "json")
        ]) else {
            return (InquiryProviderStatus(provider: .internetArchive, state: .failed, message: "Invalid query"), [])
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let response = object?["response"] as? [String: Any]
            let docs = response?["docs"] as? [[String: Any]] ?? []
            let candidates = docs.compactMap {
                internetArchiveCandidate(from: $0, lane: lane, intent: intent, profile: profile)
            }
            return (InquiryProviderStatus(provider: .internetArchive, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .internetArchive, state: .failed, message: error.localizedDescription), [])
        }
    }

    static func fetchYouTube(
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let apiKey = APIKeys.youtube, !apiKey.isEmpty else {
            // No Data API key — fall back to parsing the public results page so
            // videos still appear (they're a core source lane, not optional).
            return await fetchYouTubeViaSearchPage(query: query, lane: lane, intent: intent, profile: profile)
        }
        guard let url = searchURL(base: "https://www.googleapis.com/youtube/v3/search", queryItems: [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "15"),
            URLQueryItem(name: "order", value: "relevance"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: apiKey)
        ]) else {
            return (InquiryProviderStatus(provider: .youtube, state: .failed, message: "Invalid query"), [])
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                return (InquiryProviderStatus(provider: .youtube, state: .rateLimited, message: "YouTube quota or key rejected"), [])
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let items = object?["items"] as? [[String: Any]] ?? []
            var candidates = items.compactMap {
                youtubeCandidate(from: $0, lane: lane, intent: intent, profile: profile)
            }
            candidates = await enrichYouTubeCandidates(candidates, apiKey: apiKey)
            return (InquiryProviderStatus(provider: .youtube, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .youtube, state: .failed, message: error.localizedDescription), [])
        }
    }

    /// One cheap videos.list call attaches duration + view count to each hit,
    /// then drops sub-4-minute videos — shorts and motivation edits are the
    /// noise the user keeps dismissing, and real lectures/podcasts run long.
    /// The signals also ride into ranking as qualitySignals.
    private static func enrichYouTubeCandidates(
        _ candidates: [InquirySourceCandidate],
        apiKey: String
    ) async -> [InquirySourceCandidate] {
        let videoIds = candidates.compactMap { candidate -> String? in
            guard let url = candidate.url,
                  let id = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "v" })?.value else { return nil }
            return id
        }
        guard !videoIds.isEmpty,
              let url = searchURL(base: "https://www.googleapis.com/youtube/v3/videos", queryItems: [
                  URLQueryItem(name: "part", value: "contentDetails,statistics"),
                  URLQueryItem(name: "id", value: videoIds.joined(separator: ",")),
                  URLQueryItem(name: "key", value: apiKey)
              ]),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["items"] as? [[String: Any]] else { return candidates }

        var detailsById: [String: (seconds: Int, views: Int?)] = [:]
        for item in items {
            guard let id = item["id"] as? String else { continue }
            let duration = ((item["contentDetails"] as? [String: Any])?["duration"] as? String)
                .map(parseISO8601Duration) ?? 0
            let views = ((item["statistics"] as? [String: Any])?["viewCount"] as? String).flatMap(Int.init)
            detailsById[id] = (duration, views)
        }

        return candidates.compactMap { candidate in
            guard let url = candidate.url,
                  let id = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "v" })?.value,
                  let details = detailsById[id] else { return candidate }
            if details.seconds > 0 && details.seconds < 240 { return nil }
            var copy = candidate
            if details.seconds > 0 {
                copy.qualitySignals.append("\(details.seconds / 60) min")
            }
            if let views = details.views {
                copy.qualitySignals.append("\(formattedCount(views)) views")
            }
            return copy
        }
    }

    /// "PT1H23M45S" → seconds.
    static func parseISO8601Duration(_ raw: String) -> Int {
        var seconds = 0
        var number = ""
        for character in raw {
            if character.isNumber {
                number.append(character)
            } else {
                let value = Int(number) ?? 0
                switch character {
                case "H": seconds += value * 3600
                case "M": seconds += value * 60
                case "S": seconds += value
                default: break
                }
                number = ""
            }
        }
        return seconds
    }

    private static func formattedCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...: return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(count) / 1_000)
        default: return "\(count)"
        }
    }

    /// Keyless YouTube fallback: fetches the public results page and parses the
    /// embedded ytInitialData JSON for videoRenderer entries. Less precise than
    /// the Data API but keeps the lecture lane alive without configuration.
    static func fetchYouTubeViaSearchPage(
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let url = searchURL(base: "https://www.youtube.com/results", queryItems: [
            URLQueryItem(name: "search_query", value: query),
            URLQueryItem(name: "hl", value: "en")
        ]) else {
            return (InquiryProviderStatus(provider: .youtube, state: .failed, message: "Invalid query"), [])
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8),
                  let initialData = ytInitialData(in: html) else {
                return (InquiryProviderStatus(provider: .youtube, state: .failed, message: "Could not parse results page"), [])
            }
            let renderers = collectDictionaries(named: "videoRenderer", in: initialData)
            let candidates = renderers.prefix(12).compactMap {
                youtubeScrapedCandidate(from: $0, lane: lane, intent: intent, profile: profile)
            }
            return (InquiryProviderStatus(provider: .youtube, state: .succeeded, count: candidates.count), Array(candidates))
        } catch {
            return (InquiryProviderStatus(provider: .youtube, state: .failed, message: error.localizedDescription), [])
        }
    }

    private static func ytInitialData(in html: String) -> [String: Any]? {
        guard let markerRange = html.range(of: "var ytInitialData = ") else { return nil }
        let tail = html[markerRange.upperBound...]
        guard let endRange = tail.range(of: ";</script>") else { return nil }
        let json = String(tail[..<endRange.lowerBound])
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Recursively collects every dictionary stored under the given key — robust
    /// against YouTube reshuffling its nesting structure.
    private static func collectDictionaries(named key: String, in object: Any, limit: Int = 16) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func walk(_ node: Any) {
            guard found.count < limit else { return }
            if let dict = node as? [String: Any] {
                if let match = dict[key] as? [String: Any] {
                    found.append(match)
                }
                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }
        walk(object)
        return found
    }

    private static func youtubeScrapedCandidate(
        from renderer: [String: Any],
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) -> InquirySourceCandidate? {
        guard let videoId = renderer["videoId"] as? String, !videoId.isEmpty,
              let title = runsText(renderer["title"]), !title.isEmpty else { return nil }
        let channel = runsText(renderer["ownerText"]) ?? runsText(renderer["longBylineText"])
        let published = simpleText(renderer["publishedTimeText"])
        let views = simpleText(renderer["viewCountText"])
        let length = simpleText(renderer["lengthText"])
        // Shorts and minute-long edits are noise — a "M:SS" length under
        // four minutes never survives.
        if let length {
            let parts = length.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, parts[0] < 4 { return nil }
        }
        let snippet = runsText((renderer["detailedMetadataSnippets"] as? [[String: Any]])?.first?["snippetText"])

        return InquirySourceCandidate(
            id: stableID(provider: .youtube, key: videoId),
            provider: .youtube,
            sourceKind: .video,
            title: decodeHTMLEntities(title),
            subtitle: channel,
            url: "https://www.youtube.com/watch?v=\(videoId)",
            abstract: snippet,
            evidenceRole: lane == .teacherLecture ? .lecture : .videoExplainer,
            reason: "Deep Scout lecture candidate from YouTube.",
            qualitySignals: [channel, published, views, length, "Video"].compactMap { $0 },
            branchQuestionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            researchIntent: intent,
            sourceLane: lane
        )
    }

    private static func runsText(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        guard let runs = dict["runs"] as? [[String: Any]] else { return nil }
        let joined = runs.compactMap { $0["text"] as? String }.joined()
        return joined.isEmpty ? nil : joined
    }

    private static func simpleText(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        return (dict["simpleText"] as? String) ?? runsText(dict)
    }

    /// Podcast episodes via the iTunes Search API — keyless and stable.
    static func fetchPodcasts(
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        // Episodes AND shows in parallel: episode search finds the exact
        // conversation; show search finds the podcast whose whole beat is the
        // topic (or the favorite creator the query names).
        async let episodes = fetchPodcastEntity("podcastEpisode", query: query, lane: lane, intent: intent, profile: profile)
        async let shows = fetchPodcastEntity("podcast", query: query, lane: lane, intent: intent, profile: profile)
        let (episodeResult, showResult) = await (episodes, shows)

        switch (episodeResult, showResult) {
        case (.failure(let message), .failure):
            return (InquiryProviderStatus(provider: .podcast, state: .failed, message: message), [])
        case (.success(let episodeCandidates), .failure):
            return (InquiryProviderStatus(provider: .podcast, state: .succeeded, count: episodeCandidates.count), episodeCandidates)
        case (.failure, .success(let showCandidates)):
            return (InquiryProviderStatus(provider: .podcast, state: .succeeded, count: showCandidates.count), showCandidates)
        case (.success(let episodeCandidates), .success(let showCandidates)):
            var seen = Set(episodeCandidates.map(\.id))
            var merged = episodeCandidates
            for candidate in showCandidates where !seen.contains(candidate.id) {
                seen.insert(candidate.id)
                merged.append(candidate)
            }
            return (InquiryProviderStatus(provider: .podcast, state: .succeeded, count: merged.count), merged)
        }
    }

    private enum PodcastFetchResult {
        case success([InquirySourceCandidate])
        case failure(String)
    }

    private static func fetchPodcastEntity(
        _ entity: String,
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> PodcastFetchResult {
        guard let url = searchURL(base: "https://itunes.apple.com/search", queryItems: [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "limit", value: entity == "podcast" ? "5" : "10")
        ]) else {
            return .failure("Invalid query")
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = object?["results"] as? [[String: Any]] ?? []
            let candidates: [InquirySourceCandidate]
            if entity == "podcast" {
                candidates = results.compactMap {
                    podcastShowCandidate(from: $0, lane: lane, intent: intent, profile: profile)
                }
            } else {
                candidates = results.compactMap {
                    podcastCandidate(from: $0, lane: lane, intent: intent, profile: profile)
                }
            }
            return .success(candidates)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func podcastShowCandidate(
        from result: [String: Any],
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) -> InquirySourceCandidate? {
        guard let title = result["collectionName"] as? String, !title.isEmpty,
              let pageURL = result["collectionViewUrl"] as? String else {
            return nil
        }
        let artist = result["artistName"] as? String
        let genre = result["primaryGenreName"] as? String
        let episodeCount = result["trackCount"] as? Int
        let key = (result["collectionId"] as? Int).map(String.init) ?? pageURL

        return InquirySourceCandidate(
            id: stableID(provider: .podcast, key: "show-\(key)"),
            provider: .podcast,
            sourceKind: .video,
            title: decodeHTMLEntities(title),
            subtitle: artist ?? title,
            url: pageURL,
            abstract: genre,
            evidenceRole: .lecture,
            reason: "Podcast show whose beat covers this topic.",
            qualitySignals: [
                artist,
                episodeCount.map { "\($0) episodes" },
                "Podcast show"
            ].compactMap { $0 },
            branchQuestionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            researchIntent: intent,
            sourceLane: lane
        )
    }

    private static func podcastCandidate(
        from result: [String: Any],
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) -> InquirySourceCandidate? {
        guard let title = result["trackName"] as? String, !title.isEmpty,
              let pageURL = (result["trackViewUrl"] as? String) ?? (result["collectionViewUrl"] as? String) else {
            return nil
        }
        let show = result["collectionName"] as? String
        let releaseDate = (result["releaseDate"] as? String).map { String($0.prefix(4)) }
        let description = (result["description"] as? String) ?? (result["shortDescription"] as? String)
        let key = (result["trackId"] as? Int).map(String.init) ?? pageURL

        return InquirySourceCandidate(
            id: stableID(provider: .podcast, key: key),
            provider: .podcast,
            sourceKind: .video,
            title: decodeHTMLEntities(title),
            subtitle: show,
            publishedDate: releaseDate,
            url: pageURL,
            abstract: description,
            evidenceRole: .lecture,
            reason: "Deep Scout podcast episode from iTunes.",
            qualitySignals: [show, releaseDate.map { "Published \($0)" }, "Podcast"].compactMap { $0 },
            branchQuestionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            researchIntent: intent,
            sourceLane: lane
        )
    }

    static func openLibraryCandidate(
        from doc: [String: Any],
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) -> InquirySourceCandidate? {
        guard let title = doc["title"] as? String, !title.isEmpty else { return nil }
        let key = (doc["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authors = doc["author_name"] as? [String] ?? []
        let year = (doc["first_publish_year"] as? Int).map(String.init)
        let subjects = (doc["subject"] as? [String])?.prefix(3).joined(separator: ", ")
        let sentence = firstString(from: doc["first_sentence"])
        let url = key.map { "https://openlibrary.org\($0)" }
        let role = role(for: lane, fallback: .book)

        return InquirySourceCandidate(
            id: stableID(provider: .openLibrary, key: key ?? title),
            provider: .openLibrary,
            sourceKind: .book,
            title: decodeHTMLEntities(title),
            subtitle: subjects,
            authors: authors,
            publishedDate: year,
            url: url,
            abstract: sentence,
            evidenceRole: role,
            reason: "Deep Scout book candidate from Open Library.",
            qualitySignals: [
                year.map { "Published \($0)" },
                subjects,
                "Book"
            ].compactMap { $0 },
            branchQuestionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            researchIntent: intent,
            sourceLane: lane
        )
    }

    static func googleBooksCandidate(
        from item: [String: Any],
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) -> InquirySourceCandidate? {
        let volume = item["volumeInfo"] as? [String: Any]
        guard let title = volume?["title"] as? String, !title.isEmpty else { return nil }
        let authors = volume?["authors"] as? [String] ?? []
        let publishedDate = volume?["publishedDate"] as? String
        let year = publishedDate.map { String($0.prefix(4)) }
        let description = volume?["description"] as? String
        let publisher = volume?["publisher"] as? String
        let url = (volume?["canonicalVolumeLink"] as? String)
            ?? (volume?["infoLink"] as? String)
            ?? (volume?["previewLink"] as? String)
        let categories = (volume?["categories"] as? [String])?.prefix(2).joined(separator: ", ")
        let role = role(for: lane, fallback: .book)

        return InquirySourceCandidate(
            id: stableID(provider: .googleBooks, key: url ?? title),
            provider: .googleBooks,
            sourceKind: .book,
            title: decodeHTMLEntities(title),
            subtitle: publisher ?? categories,
            authors: authors,
            publishedDate: year,
            url: url,
            abstract: description,
            evidenceRole: role,
            reason: "Deep Scout book candidate from Google Books.",
            qualitySignals: [
                year.map { "Published \($0)" },
                publisher,
                categories,
                "Book"
            ].compactMap { $0 },
            branchQuestionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            researchIntent: intent,
            sourceLane: lane
        )
    }

    static func internetArchiveCandidate(
        from doc: [String: Any],
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) -> InquirySourceCandidate? {
        guard let identifier = doc["identifier"] as? String,
              let title = doc["title"] as? String,
              !identifier.isEmpty,
              !title.isEmpty else { return nil }
        let authors = strings(from: doc["creator"])
        let date = firstString(from: doc["date"])
        let description = firstString(from: doc["description"])
        let role = role(for: lane, fallback: .book)

        return InquirySourceCandidate(
            id: stableID(provider: .internetArchive, key: identifier),
            provider: .internetArchive,
            sourceKind: .book,
            title: decodeHTMLEntities(title),
            authors: authors,
            publishedDate: date.map { String($0.prefix(4)) },
            url: "https://archive.org/details/\(identifier)",
            abstract: description,
            evidenceRole: role,
            reason: "Deep Scout text candidate from Internet Archive.",
            qualitySignals: [
                date.map { "Published \(String($0.prefix(4)))" },
                "Archive text"
            ].compactMap { $0 },
            branchQuestionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            researchIntent: intent,
            sourceLane: lane
        )
    }

    static func youtubeCandidate(
        from item: [String: Any],
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) -> InquirySourceCandidate? {
        guard let id = item["id"] as? [String: Any],
              let videoId = id["videoId"] as? String,
              let snippet = item["snippet"] as? [String: Any],
              let title = snippet["title"] as? String,
              !videoId.isEmpty,
              !title.isEmpty else { return nil }
        let description = snippet["description"] as? String
        let channel = snippet["channelTitle"] as? String
        let publishedAt = snippet["publishedAt"] as? String
        let year = publishedAt.map { String($0.prefix(4)) }

        return InquirySourceCandidate(
            id: stableID(provider: .youtube, key: videoId),
            provider: .youtube,
            sourceKind: .video,
            title: decodeHTMLEntities(title),
            subtitle: channel,
            publishedDate: year,
            url: "https://www.youtube.com/watch?v=\(videoId)",
            abstract: description,
            evidenceRole: lane == .teacherLecture ? .lecture : .videoExplainer,
            reason: "Deep Scout lecture candidate from YouTube.",
            qualitySignals: [
                channel,
                year.map { "Published \($0)" },
                "Video"
            ].compactMap { $0 },
            branchQuestionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            researchIntent: intent,
            sourceLane: lane
        )
    }

    private static func role(for lane: InquirySourceLane, fallback: InquiryEvidenceRole) -> InquiryEvidenceRole {
        switch lane {
        case .primaryText: return .primaryText
        case .practiceGuide: return .traditionGuide
        case .teacherLecture: return .lecture
        case .scholarlyContext: return .philosophicalContext
        case .clinicalEvidence: return .review
        case .localLibrary: return .localLibrary
        case .webResource: return .webContext
        case .deepRead: return fallback
        }
    }

    private static func firstString(from value: Any?) -> String? {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if let strings = value as? [String] {
            return strings.first?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return nil
    }

    private static func strings(from value: Any?) -> [String] {
        if let string = value as? String {
            return [string].filter { !$0.isEmpty }
        }
        if let strings = value as? [String] {
            return strings.filter { !$0.isEmpty }
        }
        return []
    }

    private static func searchURL(base: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = queryItems
        return components?.url
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let decoded = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ).string else {
            return text
        }
        return decoded
    }

    private static func stableID(provider: InquirySourceProvider, key: String) -> String {
        var hash: UInt64 = 5381
        for scalar in key.lowercased().unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return "\(provider.rawValue)-\(String(hash, radix: 16))"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
