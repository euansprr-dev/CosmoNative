import Foundation

enum SwipeLabCorpus {
    static let version = 3

    static func platformFamily(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("instagram") { return "instagram" }
        if value.hasPrefix("youtube") { return "youtube" }
        if ["x", "twitter", "tweet", "thread", "twitter_thread"].contains(value) { return "x" }
        return value
    }

    @MainActor
    static func resolve(_ scope: SwipeLabScope, comparison: Bool = false) async throws -> [SwipeLabSource] {
        let atoms: [Atom]
        switch scope.kind {
        case .selection:
            atoms = try await AtomRepository.shared.fetchBatch(uuids: scope.sourceIDs)
        case .board:
            guard let boardID = scope.boardID else { return [] }
            atoms = try await AtomRepository.shared.fetchSwipeFileAtoms().filter { ($0.swipeBoardIDs ?? []).contains(boardID) }
        case .library:
            atoms = try await AtomRepository.shared.fetchSwipeFileAtoms()
        case .client:
            guard let clientID = scope.populationClientID else { return [] }
            atoms = try await AtomRepository.shared.fetchAll(type: .content).filter {
                clientIDForContent($0) == clientID && !ContentPublishStore.records(for: $0).isEmpty
            }
        }
        let perf = await ContentPerfStore.latestByContentPlatform()
        return await Task.detached(priority: .userInitiated) {
            build(atoms: atoms, scope: scope, performance: perf, comparison: comparison)
        }.value
    }

    static func clientIDForContent(_ atom: Atom) -> String? {
        guard let data = atom.metadata?.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return value["clientProfileUUID"] as? String ?? value["clientUUID"] as? String
    }

    static func build(atoms: [Atom], scope: SwipeLabScope, performance: [ContentPerfSnapshot] = [], comparison: Bool = false) -> [SwipeLabSource] {
        var seenIDs = Set<String>()
        var seenContent: [String: String] = [:]
        let bySource = Dictionary(grouping: performance, by: \.contentUuid)
        return atoms.filter { !$0.isDeleted && ($0.isSwipeFileAtom || $0.type == .content) }
            .sorted { $0.createdAt == $1.createdAt ? $0.uuid < $1.uuid : $0.createdAt > $1.createdAt }
            .compactMap { atom in
                guard seenIDs.insert(atom.uuid).inserted else { return nil }
                var source = source(atom, performance: bySource[atom.uuid] ?? [])
                if let platform = scope.platform, !platform.isEmpty, platformFamily(source.platform) != platformFamily(platform) { return nil }
                if let format = scope.format, !format.isEmpty, source.format.caseInsensitiveCompare(format.trimmingCharacters(in: .whitespaces)) != .orderedSame { return nil }
                if let start = scope.publishedAfter {
                    guard let date = source.publishedAt, date >= start else { return nil }
                }
                if let end = scope.publishedBefore {
                    guard let date = source.publishedAt, date < end else { return nil }
                }
                source.isComparison = comparison
                // Compare exact original text, ignoring whitespace; AI signatures
                // and shared titles are not enough to call two posts duplicates.
                let normalized = source.units.map(\.text).joined(separator: " ")
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if !normalized.isEmpty {
                    let key = SwipeLabHash.string(normalized)
                    source.duplicateOf = seenContent[key]
                    if seenContent[key] == nil { seenContent[key] = source.id }
                }
                return source
            }
    }

    static func source(_ atom: Atom, performance: [ContentPerfSnapshot] = []) -> SwipeLabSource {
        let analysis = atom.swipeAnalysis
        let platform = atom.researchMetadata?.contentSource ?? performance.first?.platform ?? "Unknown platform"
        let publishedAt = analysis?.publishedAt ?? ContentPublishStore.records(for: atom).first?.publishedAtDate
        var units: [SwipeLabUnit] = []
        let hash = SwipeLabHash.string(originalFingerprint(atom))
        let carousel = (atom.richContent?.instagramData?.carouselItems ?? []).sorted { $0.index < $1.index }
        let slides = (analysis?.transcriptSlides ?? []).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for slide in slides {
            let beat = analysis?.sections?.first { section in
                guard let start = section.slideStart, let end = section.slideEnd else { return false }
                return (start...max(start, end)).contains(slide.slideNumber)
            }
            let anchor = SwipeLabAnchor(sourceID: atom.uuid, sourceHash: hash,
                unitID: slide.id.uuidString, kind: .slide, label: "Slide \(slide.slideNumber)",
                quote: slide.text, slideNumber: slide.slideNumber,
                startSeconds: slide.timestamp, endSeconds: slide.endTimestamp)
            units.append(.init(anchor: anchor, job: beat?.label ?? "Slide", text: slide.text,
                               hasVisual: carousel.indices.contains(slide.slideNumber - 1) && carousel[slide.slideNumber - 1].mediaType == .image))
        }
        for (index, item) in carousel.enumerated() where item.mediaType == .image && !slides.contains(where: { $0.slideNumber == index + 1 }) {
            let anchor = SwipeLabAnchor(sourceID: atom.uuid, sourceHash: hash, unitID: item.id.uuidString,
                kind: .slide, label: "Slide \(index + 1) · image", quote: "", slideNumber: index + 1)
            units.append(.init(anchor: anchor, job: index == 0 ? "opening" : "other", text: "", hasVisual: true))
        }
        units.sort { ($0.anchor.slideNumber ?? 0) < ($1.anchor.slideNumber ?? 0) }
        // Speech remains its own modality even when a reel also has on-screen text.
        for segment in analysis?.transcriptSpeechSegments ?? [] where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let anchor = SwipeLabAnchor(sourceID: atom.uuid, sourceHash: hash,
                unitID: "speech-\(segment.id)", kind: .speech, label: timeLabel(segment.start),
                quote: segment.text, startSeconds: segment.start, endSeconds: segment.end)
            units.append(.init(anchor: anchor, job: "Speech", text: segment.text))
        }
        for unit in atom.swipeArtifactUnits {
            // The mechanic is model analysis; it must never masquerade as a quote.
            let original = [unit.headline, unit.copy].compactMap { $0 }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
            guard !original.isEmpty || unit.attachmentUUID != nil else { continue }
            let label = unit.role?.rawValue.replacingOccurrences(of: "_", with: " ").capitalized ?? "Section \(unit.index + 1)"
            let anchor = SwipeLabAnchor(sourceID: atom.uuid, sourceHash: hash, unitID: unit.id,
                                        kind: .artifact, label: label, quote: original)
            units.append(.init(anchor: anchor, job: label, text: original, hasVisual: unit.attachmentUUID != nil))
        }
        if units.isEmpty {
            let original = originalText(atom)
            var offset = 0
            for (index, paragraph) in original.components(separatedBy: "\n\n").enumerated() {
                defer { offset += paragraph.utf16.count + 2 }
                guard !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let anchor = SwipeLabAnchor(sourceID: atom.uuid, sourceHash: hash, unitID: "paragraph-\(index)",
                    kind: .text, label: "Passage \(index + 1)", quote: paragraph,
                    utf16Start: offset, utf16Length: paragraph.utf16.count)
                units.append(.init(anchor: anchor, job: index == 0 ? "Opening" : "Passage", text: paragraph))
            }
        }
        units = units.flatMap(splitUnit)
        var metrics: [SwipeLabMetricObservation] = []
        for row in performance {
            let platformPublishedAt = ContentPublishStore.records(for: atom).first { $0.platform == row.platform }?.publishedAtDate ?? (performance.count == 1 ? publishedAt : nil)
            let values: [(SwipeLabMetric, Int)] = [(.views, row.views), (.likes, row.likes), (.comments, row.comments),
                (.shares, row.shares), (.saves, row.saves), (.follows, row.followsGained)]
            for (metric, value) in values where value >= 0 {
                metrics.append(.init(metric: metric, value: value, platform: row.platform,
                    capturedAt: ISO8601.date(from: row.capturedAt), publishedAt: platformPublishedAt,
                    provenance: "Published performance snapshot"))
            }
        }
        if metrics.isEmpty {
            let values: [(SwipeLabMetric, Int?)] = [(.views, analysis?.viewsCount), (.likes, analysis?.likesCount),
                (.comments, analysis?.commentsCount), (.shares, analysis?.sharesCount)]
            for (metric, optionalValue) in values {
                guard let value = optionalValue, value >= 0 else { continue }
                metrics.append(.init(metric: metric, value: value, platform: platform,
                    capturedAt: nil, publishedAt: publishedAt, provenance: "Saved post · capture time unavailable"))
            }
        }
        return .init(atom: atom, title: atom.title ?? "Untitled post", creator: atom.richContent?.author ?? atom.richContent?.instagramData?.authorUsername ?? "Unknown creator",
                     creatorID: analysis?.creatorUUID ?? clientIDForContent(atom), platform: platform,
                     format: analysis?.swipeContentFormat?.rawValue ?? atom.swipeKind.rawValue,
                     contentHash: hash, units: units, metrics: metrics, publishedAt: publishedAt)
    }

    static func originalText(_ atom: Atom) -> String {
        if let transcript = atom.richContent?.transcript, !transcript.isEmpty { return transcript }
        guard let body = atom.body, !body.isEmpty else { return "" }
        if let data = body.data(using: .utf8), let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) {
            return segments.map(\.text).joined(separator: " ")
        }
        return body
    }

    static func splitUnit(_ unit: SwipeLabUnit) -> [SwipeLabUnit] {
        guard unit.text.count > 4000 else { return [unit] }
        var remaining = unit.text[...]
        var offset = 0
        var parts: [SwipeLabUnit] = []
        while !remaining.isEmpty {
            let slice = String(remaining.prefix(4000))
            var part = unit
            part.text = slice
            part.anchor.quote = slice
            part.anchor.utf16Start = (unit.anchor.utf16Start ?? 0) + offset
            part.anchor.utf16Length = slice.utf16.count
            part.anchor.label += " · part \(parts.count + 1)"
            parts.append(part)
            offset += slice.utf16.count
            remaining = remaining.dropFirst(slice.count)
        }
        return parts
    }

    static func originalFingerprint(_ atom: Atom) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let slides = (try? encoder.encode(atom.swipeAnalysis?.transcriptSlides)) ?? Data()
        let speech = (try? encoder.encode(atom.swipeAnalysis?.transcriptSpeechSegments)) ?? Data()
        let artifact = atom.swipeArtifactUnits.map { "\($0.id)|\($0.headline ?? "")|\($0.copy ?? "")|\($0.attachmentUUID ?? "")" }.joined(separator: "\n")
        let media = atom.richContent?.instagramData?.carouselItems?.map { "\($0.id)|\($0.mediaURL.absoluteString)" }.joined(separator: "\n") ?? ""
        return [String(data: slides, encoding: .utf8) ?? "", String(data: speech, encoding: .utf8) ?? "",
                artifact, originalText(atom), media].joined(separator: "\n")
    }

    static func timeLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

enum SwipeLabStatistics {
    struct Cohort: Identifiable, Sendable {
        var label: String
        var count: Int
        var missing: Int
        var median: Double?
        var captureTimesKnown: Int
        var id: String { label }
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func cohort(_ sources: [SwipeLabSource], metric: SwipeLabMetric, label: String) -> Cohort {
        let eligible = sources.filter { $0.duplicateOf == nil }
        let observations = eligible.compactMap { $0.metrics.first { $0.metric == metric } }
        return .init(label: label, count: observations.count, missing: eligible.count - observations.count,
                     median: median(observations.map { Double($0.value) }),
                     captureTimesKnown: observations.filter { $0.capturedAt != nil }.count)
    }

    /// Same creator/format/platform and observation age. A timeless scraped
    /// count never becomes a made-up day-seven observation.
    static func matchedBaseline(for source: SwipeLabSource, in candidates: [SwipeLabSource], metric: SwipeLabMetric) -> (median: Double, count: Int)? {
        guard let creator = source.creatorID,
              let observation = source.metrics.first(where: { $0.metric == metric }),
              let age = observation.ageHours else { return nil }
        let values = candidates.filter {
            $0.id != source.id && $0.duplicateOf == nil && $0.creatorID == creator && $0.format == source.format
        }.compactMap { candidate -> Double? in
            guard let value = candidate.metrics.first(where: { $0.metric == metric && $0.platform == observation.platform }),
                  let candidateAge = value.ageHours,
                  abs(candidateAge - age) <= max(12, age * 0.2),
                  value.isPaid == observation.isPaid else { return nil }
            return Double(value.value)
        }
        guard values.count >= 3, let median = median(values), median > 0 else { return nil }
        return (median, values.count)
    }

    static func candidateScore(_ candidate: SwipeLabSource, relativeTo source: SwipeLabSource) -> Int {
        guard candidate.id != source.id, candidate.duplicateOf == nil else { return -1 }
        var score = candidate.platform == source.platform ? 3 : 0
        if candidate.format == source.format { score += 3 }
        if let creator = source.creatorID, creator == candidate.creatorID { score += 5 }
        if let first = source.publishedAt, let second = candidate.publishedAt,
           abs(first.timeIntervalSince(second)) < 90 * 86_400 { score += 1 }
        return score
    }
}
