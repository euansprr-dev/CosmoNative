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
        let archiveQuery = "(\(query)) AND mediatype:(texts)"
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
            return (InquiryProviderStatus(provider: .youtube, state: .missingKey, message: "Add a YouTube API key to include videos"), [])
        }
        guard let url = searchURL(base: "https://www.googleapis.com/youtube/v3/search", queryItems: [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "8"),
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
            let candidates = items.compactMap {
                youtubeCandidate(from: $0, lane: lane, intent: intent, profile: profile)
            }
            return (InquiryProviderStatus(provider: .youtube, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .youtube, state: .failed, message: error.localizedDescription), [])
        }
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
