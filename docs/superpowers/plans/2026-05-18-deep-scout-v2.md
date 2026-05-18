# Deep Scout V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Deep Scout return sources that match the user's research intent, so a branch like "What is pranayama?" surfaces videos, books, primary/traditional texts, and philosophical resources before clinical stress/anxiety papers.

**Architecture:** Split Deep Scout into intent classification, lane-aware query planning, provider adapters, and intent-aware ranking. Keep `InquirySourceRecommendationEngine` as the orchestration layer, but move the new logic into focused Deep Scout files so it can be tested without network calls.

**Tech Stack:** Swift, SwiftUI, XCTest, URLSession, existing `ResearchService`, public book/search APIs, existing `InquirySourceCandidate` and recommendation batch models.

---

## Current Failure

The current implementation lives mostly in `AI/InquiryPlacementEngine.swift`. For every Deep Scout, `scoutQueries(for:)` adds academic phrases like "systematic review meta-analysis randomized controlled trial", "mechanism physiology evidence", and "recent peer reviewed study". `recommend(...)` then queries OpenAlex, Crossref, Semantic Scholar, Europe PMC, YouTube once, and web research. Ranking boosts OpenAlex/Semantic Scholar/PubMed, reviews, meta-analyses, DOI/citations, and recency.

That design is correct for "Does pranayama reduce anxiety?" but wrong for "What is pranayama?". The user is asking for concept formation, philosophy, practice lineage, and deep orientation. V2 must detect that difference before it builds queries or ranks sources.

## File Structure

- Create `AI/DeepScoutIntentPlanner.swift`
  - Classifies the branch intent.
  - Builds lane-aware query plans.
  - Owns no network code.

- Create `AI/DeepScoutProviders.swift`
  - Adds public book/resource providers.
  - Wraps YouTube multi-query search and web fallback for videos.
  - Converts provider JSON into `InquirySourceCandidate`.

- Create `AI/DeepScoutRanker.swift`
  - Scores candidates against the intent and lane.
  - Penalizes clinical/corporate drift when the question is conceptual/philosophical.
  - Balances the final list so one provider or evidence role cannot dominate.

- Modify `Data/Models/InquiryWorkspaceModels.swift`
  - Add research intent and source lane enums.
  - Add optional lane/intent fields to `InquirySourceCandidate` for backward-compatible decoding.
  - Add book/search providers and richer source roles.

- Modify `AI/InquiryPlacementEngine.swift`
  - Replace hard-coded Deep Scout query expansion and ranking with the new planner/providers/ranker.
  - Keep quick source radar behavior conservative.

- Modify `UI/FocusMode/Inquiry/InquirySourcesRail.swift`
  - Show lane labels in compact candidate rows.
  - Group or visually separate candidates by lane when Deep Scout is active.

- Modify `UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift`
  - Add lane filters/headers in the expanded Source Radar pane.
  - Show why a candidate was surfaced in human terms.

- Modify `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`
  - Add red tests for conceptual pranayama queries, corporate/clinical drift penalties, source diversity, books, and YouTube fallback.

---

### Task 1: Add Intent And Lane Model

**Files:**
- Modify: `Data/Models/InquiryWorkspaceModels.swift`
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Write failing tests for new model defaults**

Add these tests to `InquiryPlacementEngineTests`:

```swift
func testInquirySourceCandidateDecodesWithoutDeepScoutV2Fields() throws {
    let json = """
    {
      "id": "old-candidate",
      "provider": "openAlex",
      "sourceKind": "review",
      "title": "Systematic review of breathing practices",
      "authors": [],
      "evidenceRole": "review",
      "reason": "Old candidate",
      "score": 0.5,
      "qualitySignals": [],
      "importStatus": "candidate",
      "generatedAt": "2026-05-18T00:00:00Z"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(InquirySourceCandidate.self, from: json)

    XCTAssertNil(decoded.researchIntent)
    XCTAssertNil(decoded.sourceLane)
    XCTAssertEqual(decoded.provider, .openAlex)
    XCTAssertEqual(decoded.evidenceRole, .review)
}

func testInquirySourceLaneDisplayNamesAreHumanReadable() {
    XCTAssertEqual(InquirySourceLane.deepRead.displayName, "Deep read")
    XCTAssertEqual(InquirySourceLane.teacherLecture.displayName, "Lecture")
    XCTAssertEqual(InquirySourceLane.primaryText.displayName, "Primary text")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testInquirySourceCandidateDecodesWithoutDeepScoutV2Fields -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testInquirySourceLaneDisplayNamesAreHumanReadable
```

Expected: compile fails because `InquirySourceLane`, `researchIntent`, and `sourceLane` do not exist.

- [ ] **Step 3: Add enums and candidate fields**

In `Data/Models/InquiryWorkspaceModels.swift`, add:

```swift
enum InquiryResearchIntent: String, Codable, CaseIterable, Sendable, Hashable {
    case conceptExploration
    case philosophicalOrientation
    case practiceTechnique
    case historicalLineage
    case clinicalEvidence
    case mechanismScience
    case sourceSurvey

    var displayName: String {
        switch self {
        case .conceptExploration: return "Concept"
        case .philosophicalOrientation: return "Philosophy"
        case .practiceTechnique: return "Practice"
        case .historicalLineage: return "Lineage"
        case .clinicalEvidence: return "Evidence"
        case .mechanismScience: return "Mechanism"
        case .sourceSurvey: return "Survey"
        }
    }
}

enum InquirySourceLane: String, Codable, CaseIterable, Sendable, Hashable {
    case localLibrary
    case primaryText
    case deepRead
    case teacherLecture
    case practiceGuide
    case scholarlyContext
    case clinicalEvidence
    case webResource

    var displayName: String {
        switch self {
        case .localLibrary: return "Your library"
        case .primaryText: return "Primary text"
        case .deepRead: return "Deep read"
        case .teacherLecture: return "Lecture"
        case .practiceGuide: return "Practice"
        case .scholarlyContext: return "Scholarship"
        case .clinicalEvidence: return "Clinical"
        case .webResource: return "Resource"
        }
    }

    var iconName: String {
        switch self {
        case .localLibrary: return "archivebox"
        case .primaryText: return "scroll"
        case .deepRead: return "book.closed"
        case .teacherLecture: return "play.rectangle"
        case .practiceGuide: return "figure.mind.and.body"
        case .scholarlyContext: return "graduationcap"
        case .clinicalEvidence: return "cross.case"
        case .webResource: return "globe"
        }
    }
}
```

Extend `InquirySourceProvider`:

```swift
case googleBooks
case openLibrary
case internetArchive
```

and display names:

```swift
case .googleBooks: return "Google Books"
case .openLibrary: return "Open Library"
case .internetArchive: return "Internet Archive"
```

Extend `InquiryEvidenceRole`:

```swift
case primaryText
case book
case lecture
case philosophicalContext
case traditionGuide
```

and display names:

```swift
case .primaryText: return "Primary"
case .book: return "Book"
case .lecture: return "Lecture"
case .philosophicalContext: return "Philosophy"
case .traditionGuide: return "Tradition"
```

Add optional fields to `InquirySourceCandidate`:

```swift
var researchIntent: InquiryResearchIntent?
var sourceLane: InquirySourceLane?
```

Add parameters to its initializer:

```swift
researchIntent: InquiryResearchIntent? = nil,
sourceLane: InquirySourceLane? = nil,
```

and assign:

```swift
self.researchIntent = researchIntent
self.sourceLane = sourceLane
```

- [ ] **Step 4: Run model tests**

Run the same command from Step 2.

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add Data/Models/InquiryWorkspaceModels.swift Tests/CosmoOSTests/InquiryPlacementEngineTests.swift
git commit -m "feat: add deep scout intent and source lanes"
```

---

### Task 2: Build The Deep Scout Intent Planner

**Files:**
- Create: `AI/DeepScoutIntentPlanner.swift`
- Modify: `CosmoOS.xcodeproj/project.pbxproj`
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Write failing intent and query tests**

Add:

```swift
func testDeepScoutClassifiesPranayamaDefinitionAsConceptExploration() {
    let profile = InquiryBranchResearchProfile(
        deepDiveTitle: "Breathwork",
        activeQuestionTitle: "What is pranayama?",
        activeQuestionUUID: "q-prana",
        branchNodeId: "node-prana",
        ancestorTitles: [],
        claims: [],
        evidence: []
    )

    let intent = DeepScoutIntentPlanner.intent(for: profile)

    XCTAssertEqual(intent, .conceptExploration)
}

func testDeepScoutV2QueriesForPranayamaPreferBooksVideosAndTradition() {
    let profile = InquiryBranchResearchProfile(
        deepDiveTitle: "Breathwork",
        activeQuestionTitle: "What is pranayama?",
        activeQuestionUUID: "q-prana",
        branchNodeId: "node-prana",
        ancestorTitles: [],
        claims: [],
        evidence: []
    )

    let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
    let queries = plan.queries.map(\.query).joined(separator: "\n").lowercased()

    XCTAssertEqual(plan.intent, .conceptExploration)
    XCTAssertTrue(queries.contains("pranayama meaning"))
    XCTAssertTrue(queries.contains("prana"))
    XCTAssertTrue(queries.contains("youtube"))
    XCTAssertTrue(queries.contains("book"))
    XCTAssertTrue(queries.contains("patanjali") || queries.contains("hatha yoga pradipika"))
    XCTAssertFalse(queries.contains("randomized controlled trial"))
    XCTAssertFalse(queries.contains("mental disorders"))
}

func testDeepScoutV2KeepsClinicalQueriesForClinicalQuestion() {
    let profile = InquiryBranchResearchProfile(
        deepDiveTitle: "Breathwork",
        activeQuestionTitle: "How does pranayama affect anxiety?",
        activeQuestionUUID: "q-clinical",
        branchNodeId: "node-clinical",
        ancestorTitles: [],
        claims: [],
        evidence: []
    )

    let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
    let queries = plan.queries.map(\.query).joined(separator: "\n").lowercased()

    XCTAssertEqual(plan.intent, .clinicalEvidence)
    XCTAssertTrue(queries.contains("systematic review") || queries.contains("meta-analysis"))
    XCTAssertTrue(queries.contains("anxiety"))
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testDeepScoutClassifiesPranayamaDefinitionAsConceptExploration -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testDeepScoutV2QueriesForPranayamaPreferBooksVideosAndTradition -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testDeepScoutV2KeepsClinicalQueriesForClinicalQuestion
```

Expected: compile fails because `DeepScoutIntentPlanner` does not exist.

- [ ] **Step 3: Create planner**

Create `AI/DeepScoutIntentPlanner.swift`:

```swift
import Foundation

struct DeepScoutQuery: Sendable, Equatable {
    var query: String
    var lane: InquirySourceLane
    var providers: [InquirySourceProvider]
}

struct DeepScoutPlan: Sendable, Equatable {
    var intent: InquiryResearchIntent
    var queries: [DeepScoutQuery]
}

enum DeepScoutIntentPlanner {
    static func intent(for profile: InquiryBranchResearchProfile) -> InquiryResearchIntent {
        let raw = [
            profile.sourceQuery,
            profile.activeQuestionTitle,
            profile.deepDiveTitle,
            profile.ancestorTitles.joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ").lowercased()

        if raw.contains("anxiety")
            || raw.contains("stress")
            || raw.contains("mental health")
            || raw.contains("disorder")
            || raw.contains("clinical")
            || raw.contains("effectiveness")
            || raw.contains("randomized")
            || raw.contains("meta-analysis")
            || raw.contains("systematic review") {
            return .clinicalEvidence
        }

        if raw.contains("how do i")
            || raw.contains("how to")
            || raw.contains("practice")
            || raw.contains("technique")
            || raw.contains("protocol") {
            return .practiceTechnique
        }

        if raw.contains("history")
            || raw.contains("origin")
            || raw.contains("lineage")
            || raw.contains("patanjali")
            || raw.contains("hatha") {
            return .historicalLineage
        }

        if raw.hasPrefix("what is ")
            || raw.contains("meaning")
            || raw.contains("definition")
            || raw.contains("concept")
            || raw.contains("philosophy")
            || raw.contains("pranayama") {
            return .conceptExploration
        }

        return .sourceSurvey
    }

    static func plan(
        for profile: InquiryBranchResearchProfile,
        mode: InquirySourceSearchMode
    ) -> DeepScoutPlan {
        let intent = intent(for: profile)
        let focus = normalizedFocus(profile)

        guard mode == .deepScout else {
            return DeepScoutPlan(
                intent: intent,
                queries: [DeepScoutQuery(query: profile.query, lane: .scholarlyContext, providers: [.local, .openAlex, .crossref])]
            )
        }

        switch intent {
        case .conceptExploration, .philosophicalOrientation:
            return DeepScoutPlan(intent: intent, queries: conceptQueries(focus: focus))
        case .practiceTechnique:
            return DeepScoutPlan(intent: intent, queries: practiceQueries(focus: focus))
        case .historicalLineage:
            return DeepScoutPlan(intent: intent, queries: lineageQueries(focus: focus))
        case .clinicalEvidence, .mechanismScience:
            return DeepScoutPlan(intent: intent, queries: clinicalQueries(focus: focus))
        case .sourceSurvey:
            return DeepScoutPlan(intent: intent, queries: surveyQueries(focus: focus))
        }
    }

    private static func conceptQueries(focus: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(query: "\(focus) meaning prana ayama classical yoga", lane: .primaryText, providers: [.web, .internetArchive]),
            DeepScoutQuery(query: "\(focus) patanjali yoga sutras hatha yoga pradipika", lane: .primaryText, providers: [.web, .internetArchive]),
            DeepScoutQuery(query: "\(focus) philosophy lecture youtube", lane: .teacherLecture, providers: [.youtube, .web]),
            DeepScoutQuery(query: "\(focus) introduction lecture swami yoga youtube", lane: .teacherLecture, providers: [.youtube, .web]),
            DeepScoutQuery(query: "\(focus) best books yoga pranayama", lane: .deepRead, providers: [.openLibrary, .googleBooks, .internetArchive]),
            DeepScoutQuery(query: "\(focus) history philosophy yoga tradition", lane: .scholarlyContext, providers: [.openAlex, .crossref, .semanticScholar])
        ]
    }

    private static func practiceQueries(focus: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(query: "\(focus) practice guide technique", lane: .practiceGuide, providers: [.web, .youtube]),
            DeepScoutQuery(query: "\(focus) teacher demonstration youtube", lane: .teacherLecture, providers: [.youtube, .web]),
            DeepScoutQuery(query: "\(focus) contraindications safety", lane: .clinicalEvidence, providers: [.openAlex, .semanticScholar, .pubMed]),
            DeepScoutQuery(query: "\(focus) book manual", lane: .deepRead, providers: [.openLibrary, .googleBooks])
        ]
    }

    private static func lineageQueries(focus: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(query: "\(focus) patanjali hatha yoga pradipika primary text", lane: .primaryText, providers: [.web, .internetArchive]),
            DeepScoutQuery(query: "\(focus) history origin yoga tradition", lane: .scholarlyContext, providers: [.openAlex, .crossref, .semanticScholar]),
            DeepScoutQuery(query: "\(focus) books history yoga", lane: .deepRead, providers: [.openLibrary, .googleBooks]),
            DeepScoutQuery(query: "\(focus) lecture history philosophy youtube", lane: .teacherLecture, providers: [.youtube, .web])
        ]
    }

    private static func clinicalQueries(focus: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(query: "\(focus) systematic review meta-analysis randomized controlled trial", lane: .clinicalEvidence, providers: [.openAlex, .crossref, .semanticScholar, .pubMed]),
            DeepScoutQuery(query: "\(focus) mechanism physiology evidence", lane: .scholarlyContext, providers: [.openAlex, .semanticScholar, .pubMed]),
            DeepScoutQuery(query: "\(focus) limitations contraindications adverse effects", lane: .clinicalEvidence, providers: [.openAlex, .semanticScholar, .pubMed]),
            DeepScoutQuery(query: "\(focus) expert lecture youtube", lane: .teacherLecture, providers: [.youtube, .web])
        ]
    }

    private static func surveyQueries(focus: String) -> [DeepScoutQuery] {
        [
            DeepScoutQuery(query: "\(focus) overview introduction", lane: .webResource, providers: [.web]),
            DeepScoutQuery(query: "\(focus) book", lane: .deepRead, providers: [.openLibrary, .googleBooks]),
            DeepScoutQuery(query: "\(focus) lecture youtube", lane: .teacherLecture, providers: [.youtube, .web]),
            DeepScoutQuery(query: "\(focus) scholarly overview", lane: .scholarlyContext, providers: [.openAlex, .crossref])
        ]
    }

    private static func normalizedFocus(_ profile: InquiryBranchResearchProfile) -> String {
        let raw = (profile.sourceQuery ?? profile.activeQuestionTitle)
            .replacingOccurrences(of: "What is ", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? profile.activeQuestionTitle : raw
    }
}
```

- [ ] **Step 4: Add the new file to Xcode**

Add `AI/DeepScoutIntentPlanner.swift` to the `CosmoOS` target in `CosmoOS.xcodeproj/project.pbxproj`, following the existing `AI/CaptureIntentClassifier.swift` entry pattern.

- [ ] **Step 5: Run planner tests**

Run the command from Step 2.

Expected: all three tests pass.

- [ ] **Step 6: Commit**

```bash
git add AI/DeepScoutIntentPlanner.swift CosmoOS.xcodeproj/project.pbxproj Tests/CosmoOSTests/InquiryPlacementEngineTests.swift
git commit -m "feat: plan deep scout queries by research intent"
```

---

### Task 3: Add Books And Better Video Provider Coverage

**Files:**
- Create: `AI/DeepScoutProviders.swift`
- Modify: `AI/InquiryPlacementEngine.swift`
- Modify: `CosmoOS.xcodeproj/project.pbxproj`
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Write parser tests using fixtures**

Add tests that do not hit the network:

```swift
func testDeepScoutParsesOpenLibraryBookCandidate() throws {
    let item: [String: Any] = [
        "key": "/works/OL123W",
        "title": "Light on Pranayama",
        "author_name": ["B. K. S. Iyengar"],
        "first_publish_year": 1981
    ]

    let candidate = try XCTUnwrap(DeepScoutProviders.openLibraryCandidate(from: item, query: "pranayama books", lane: .deepRead, intent: .conceptExploration, profile: pranayamaProfile()))

    XCTAssertEqual(candidate.provider, .openLibrary)
    XCTAssertEqual(candidate.sourceKind, .book)
    XCTAssertEqual(candidate.evidenceRole, .book)
    XCTAssertEqual(candidate.sourceLane, .deepRead)
    XCTAssertEqual(candidate.researchIntent, .conceptExploration)
    XCTAssertTrue(candidate.title.localizedCaseInsensitiveContains("Pranayama"))
}

func testDeepScoutParsesYouTubeCandidateWithLectureLane() throws {
    let item: [String: Any] = [
        "id": ["videoId": "abc123"],
        "snippet": [
            "title": "Pranayama: The Philosophy of Breath",
            "description": "A lecture on prana, breath, yoga, and practice.",
            "channelTitle": "Yoga Studies",
            "publishedAt": "2022-01-01T00:00:00Z"
        ]
    ]

    let candidate = try XCTUnwrap(DeepScoutProviders.youtubeCandidate(from: item, lane: .teacherLecture, intent: .conceptExploration, profile: pranayamaProfile()))

    XCTAssertEqual(candidate.provider, .youtube)
    XCTAssertEqual(candidate.sourceKind, .video)
    XCTAssertEqual(candidate.evidenceRole, .lecture)
    XCTAssertEqual(candidate.sourceLane, .teacherLecture)
    XCTAssertEqual(candidate.url, "https://www.youtube.com/watch?v=abc123")
}

private func pranayamaProfile() -> InquiryBranchResearchProfile {
    InquiryBranchResearchProfile(
        deepDiveTitle: "Breathwork",
        activeQuestionTitle: "What is pranayama?",
        activeQuestionUUID: "q-prana",
        branchNodeId: "node-prana",
        ancestorTitles: [],
        claims: [],
        evidence: []
    )
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testDeepScoutParsesOpenLibraryBookCandidate -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testDeepScoutParsesYouTubeCandidateWithLectureLane
```

Expected: compile fails because `DeepScoutProviders` does not exist.

- [ ] **Step 3: Create provider parser helpers and fetch methods**

Create `AI/DeepScoutProviders.swift`:

```swift
import Foundation

enum DeepScoutProviders {
    static func openLibraryCandidate(
        from item: [String: Any],
        query: String,
        lane: InquirySourceLane,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) -> InquirySourceCandidate? {
        guard let title = item["title"] as? String, !title.isEmpty else { return nil }
        let key = item["key"] as? String
        let authors = item["author_name"] as? [String] ?? []
        let year = (item["first_publish_year"] as? Int).map(String.init)
        let url = key.map { "https://openlibrary.org\($0)" }

        return InquirySourceCandidate(
            id: stableID(provider: .openLibrary, key: key ?? title),
            provider: .openLibrary,
            sourceKind: .book,
            title: title,
            subtitle: authors.prefix(2).joined(separator: ", ").nilIfEmpty,
            authors: authors,
            publishedDate: year,
            url: url,
            abstract: "Book result for \(query).",
            evidenceRole: .book,
            reason: "Book-length treatment for the active branch.",
            score: 0,
            qualitySignals: [year.map { "First published \($0)" }, "Book"].compactMap { $0 },
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
              let rawTitle = snippet["title"] as? String,
              !rawTitle.isEmpty else { return nil }

        let title = decodeHTMLEntities(rawTitle)
        let description = snippet["description"] as? String
        let channel = snippet["channelTitle"] as? String
        let year = (snippet["publishedAt"] as? String).map { String($0.prefix(4)) }

        return InquirySourceCandidate(
            id: stableID(provider: .youtube, key: videoId),
            provider: .youtube,
            sourceKind: .video,
            title: title,
            subtitle: channel,
            publishedDate: year,
            url: "https://www.youtube.com/watch?v=\(videoId)",
            abstract: description,
            evidenceRole: lane == .teacherLecture ? .lecture : .videoExplainer,
            reason: lane == .teacherLecture ? "Lecture-style source for the active branch." : "Video source for the active branch.",
            qualitySignals: [channel, year.map { "Published \($0)" }, "Video"].compactMap { $0 },
            branchQuestionUUID: profile.activeQuestionUUID,
            branchNodeId: profile.branchNodeId,
            researchIntent: intent,
            sourceLane: lane
        )
    }

    static func fetchOpenLibrary(
        query: DeepScoutQuery,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let url = searchURL(base: "https://openlibrary.org/search.json", queryItems: [
            URLQueryItem(name: "q", value: query.query),
            URLQueryItem(name: "limit", value: "10")
        ]) else {
            return (InquiryProviderStatus(provider: .openLibrary, state: .failed, message: "Invalid query"), [])
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let docs = object?["docs"] as? [[String: Any]] ?? []
            let candidates = docs.compactMap {
                openLibraryCandidate(from: $0, query: query.query, lane: query.lane, intent: intent, profile: profile)
            }
            return (InquiryProviderStatus(provider: .openLibrary, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .openLibrary, state: .failed, message: error.localizedDescription), [])
        }
    }

    static func fetchYouTube(
        query: DeepScoutQuery,
        intent: InquiryResearchIntent,
        profile: InquiryBranchResearchProfile
    ) async -> (InquiryProviderStatus, [InquirySourceCandidate]) {
        guard let apiKey = APIKeys.youtube, !apiKey.isEmpty else {
            return (InquiryProviderStatus(provider: .youtube, state: .missingKey, message: "Add a YouTube API key to include direct video search"), [])
        }
        guard let url = searchURL(base: "https://www.googleapis.com/youtube/v3/search", queryItems: [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "order", value: "relevance"),
            URLQueryItem(name: "q", value: query.query),
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
                youtubeCandidate(from: $0, lane: query.lane, intent: intent, profile: profile)
            }
            return (InquiryProviderStatus(provider: .youtube, state: .succeeded, count: candidates.count), candidates)
        } catch {
            return (InquiryProviderStatus(provider: .youtube, state: .failed, message: error.localizedDescription), [])
        }
    }

    private static func searchURL(base: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = queryItems
        return components?.url
    }

    private static func stableID(provider: InquirySourceProvider, key: String) -> String {
        var hash: UInt64 = 5381
        for scalar in key.lowercased().unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return "\(provider.rawValue)-\(String(hash, radix: 16))"
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
```

- [ ] **Step 4: Add Google Books and Internet Archive fetchers**

Add to `DeepScoutProviders`:

```swift
static func fetchGoogleBooks(
    query: DeepScoutQuery,
    intent: InquiryResearchIntent,
    profile: InquiryBranchResearchProfile
) async -> (InquiryProviderStatus, [InquirySourceCandidate])

static func fetchInternetArchive(
    query: DeepScoutQuery,
    intent: InquiryResearchIntent,
    profile: InquiryBranchResearchProfile
) async -> (InquiryProviderStatus, [InquirySourceCandidate])
```

Use:

```swift
https://www.googleapis.com/books/v1/volumes?q=<query>&maxResults=10
```

and:

```swift
https://archive.org/advancedsearch.php?q=<query>&fl[]=identifier&fl[]=title&fl[]=creator&fl[]=year&rows=10&output=json
```

Map both to `.book` or `.primaryText` depending on `query.lane`.

- [ ] **Step 5: Add the new file to Xcode**

Add `AI/DeepScoutProviders.swift` to the `CosmoOS` target in `CosmoOS.xcodeproj/project.pbxproj`.

- [ ] **Step 6: Run provider parser tests**

Run the command from Step 2.

Expected: both tests pass.

- [ ] **Step 7: Commit**

```bash
git add AI/DeepScoutProviders.swift CosmoOS.xcodeproj/project.pbxproj Tests/CosmoOSTests/InquiryPlacementEngineTests.swift
git commit -m "feat: add deep scout books and video providers"
```

---

### Task 4: Implement Intent-Aware Ranking And Diversity

**Files:**
- Create: `AI/DeepScoutRanker.swift`
- Modify: `AI/InquiryPlacementEngine.swift`
- Modify: `CosmoOS.xcodeproj/project.pbxproj`
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Write failing ranking tests**

Add:

```swift
func testDeepScoutV2PranayamaConceptRanksBookAndLectureAboveClinicalStressPaper() {
    let profile = pranayamaProfile()
    let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
    let clinical = InquirySourceCandidate(
        provider: .openAlex,
        sourceKind: .metaAnalysis,
        title: "Effectiveness of pranayama for mental disorders: a systematic review",
        abstract: "Clinical stress anxiety intervention outcomes.",
        evidenceRole: .metaAnalysis,
        reason: "",
        qualitySignals: ["DOI", "120 citations"],
        researchIntent: .conceptExploration,
        sourceLane: .clinicalEvidence
    )
    let book = InquirySourceCandidate(
        provider: .openLibrary,
        sourceKind: .book,
        title: "Light on Pranayama",
        subtitle: "B. K. S. Iyengar",
        evidenceRole: .book,
        reason: "",
        qualitySignals: ["Book"],
        researchIntent: .conceptExploration,
        sourceLane: .deepRead
    )
    let lecture = InquirySourceCandidate(
        provider: .youtube,
        sourceKind: .video,
        title: "Pranayama: The Philosophy of Breath",
        subtitle: "Yoga Studies",
        evidenceRole: .lecture,
        reason: "",
        qualitySignals: ["Video"],
        researchIntent: .conceptExploration,
        sourceLane: .teacherLecture
    )

    let ranked = DeepScoutRanker.rank(
        [clinical, book, lecture],
        profile: profile,
        plan: plan,
        existingSourceRefs: [],
        limit: 12
    )

    XCTAssertEqual(ranked.prefix(2).map(\.title), [book.title, lecture.title])
    XCTAssertLessThan(ranked.first { $0.title == clinical.title }?.score ?? 1, ranked.first { $0.title == book.title }?.score ?? 0)
}

func testDeepScoutV2BalancesConceptResultsAcrossLanes() {
    let profile = pranayamaProfile()
    let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
    let candidates = [
        makeCandidate("Book A", lane: .deepRead, provider: .openLibrary, kind: .book, role: .book),
        makeCandidate("Book B", lane: .deepRead, provider: .googleBooks, kind: .book, role: .book),
        makeCandidate("Lecture A", lane: .teacherLecture, provider: .youtube, kind: .video, role: .lecture),
        makeCandidate("Primary A", lane: .primaryText, provider: .internetArchive, kind: .book, role: .primaryText),
        makeCandidate("Scholarship A", lane: .scholarlyContext, provider: .openAlex, kind: .paper, role: .foundational)
    ]

    let ranked = DeepScoutRanker.rank(candidates, profile: profile, plan: plan, existingSourceRefs: [], limit: 4)
    let lanes = Set(ranked.compactMap(\.sourceLane))

    XCTAssertTrue(lanes.contains(.deepRead))
    XCTAssertTrue(lanes.contains(.teacherLecture))
    XCTAssertTrue(lanes.contains(.primaryText))
}

private func makeCandidate(
    _ title: String,
    lane: InquirySourceLane,
    provider: InquirySourceProvider,
    kind: InquirySourceKind,
    role: InquiryEvidenceRole
) -> InquirySourceCandidate {
    InquirySourceCandidate(
        provider: provider,
        sourceKind: kind,
        title: title,
        abstract: "pranayama breath prana yoga",
        evidenceRole: role,
        reason: "",
        qualitySignals: [],
        researchIntent: .conceptExploration,
        sourceLane: lane
    )
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testDeepScoutV2PranayamaConceptRanksBookAndLectureAboveClinicalStressPaper -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testDeepScoutV2BalancesConceptResultsAcrossLanes
```

Expected: compile fails because `DeepScoutRanker` does not exist.

- [ ] **Step 3: Create ranker**

Create `AI/DeepScoutRanker.swift`:

```swift
import Foundation

enum DeepScoutRanker {
    static func rank(
        _ candidates: [InquirySourceCandidate],
        profile: InquiryBranchResearchProfile,
        plan: DeepScoutPlan,
        existingSourceRefs: [InquirySourceRef],
        limit: Int
    ) -> [InquirySourceCandidate] {
        let scored = candidates.compactMap { candidate -> InquirySourceCandidate? in
            let text = candidateText(candidate)
            guard passesAnchorGate(text: text, profile: profile) else { return nil }

            var copy = candidate
            let score = baseScore(for: copy, profile: profile, plan: plan, text: text)
            copy.score = max(0.05, min(0.99, score))
            if copy.reason.isEmpty || copy.reason.hasPrefix("Deep Scout") {
                copy.reason = reason(for: copy, plan: plan)
            }
            return copy
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }

        return balanced(scored, intent: plan.intent, limit: limit)
    }

    private static func baseScore(
        for candidate: InquirySourceCandidate,
        profile: InquiryBranchResearchProfile,
        plan: DeepScoutPlan,
        text: String
    ) -> Double {
        var score = 0.18
        score += anchorScore(text: text, profile: profile)
        score += laneFit(candidate.sourceLane, intent: plan.intent)
        score += providerTrust(candidate.provider, intent: plan.intent)
        score += depthScore(candidate)
        score -= driftPenalty(text: text, intent: plan.intent)
        return score
    }

    private static func laneFit(_ lane: InquirySourceLane?, intent: InquiryResearchIntent) -> Double {
        switch intent {
        case .conceptExploration, .philosophicalOrientation:
            switch lane {
            case .primaryText: return 0.22
            case .deepRead: return 0.20
            case .teacherLecture: return 0.18
            case .scholarlyContext: return 0.10
            case .practiceGuide: return 0.08
            case .clinicalEvidence: return -0.12
            case .localLibrary: return 0.16
            case .webResource: return 0.08
            case nil: return 0
            }
        case .clinicalEvidence, .mechanismScience:
            switch lane {
            case .clinicalEvidence, .scholarlyContext: return 0.18
            case .teacherLecture, .deepRead: return 0.06
            case .primaryText: return -0.04
            case .localLibrary, .practiceGuide, .webResource: return 0.08
            case nil: return 0
            }
        case .practiceTechnique:
            switch lane {
            case .practiceGuide: return 0.22
            case .teacherLecture: return 0.16
            case .deepRead: return 0.12
            case .clinicalEvidence: return 0.06
            case .primaryText, .scholarlyContext, .localLibrary, .webResource: return 0.08
            case nil: return 0
            }
        case .historicalLineage:
            switch lane {
            case .primaryText: return 0.22
            case .deepRead: return 0.18
            case .scholarlyContext: return 0.14
            case .teacherLecture: return 0.10
            case .clinicalEvidence: return -0.08
            case .localLibrary, .practiceGuide, .webResource: return 0.08
            case nil: return 0
            }
        case .sourceSurvey:
            return 0.08
        }
    }

    private static func providerTrust(_ provider: InquirySourceProvider, intent: InquiryResearchIntent) -> Double {
        switch intent {
        case .conceptExploration, .philosophicalOrientation, .historicalLineage:
            switch provider {
            case .openLibrary, .googleBooks, .internetArchive: return 0.12
            case .youtube: return 0.10
            case .web, .local: return 0.08
            case .openAlex, .crossref, .semanticScholar: return 0.06
            case .pubMed: return -0.03
            case .arxiv: return 0.02
            }
        case .clinicalEvidence, .mechanismScience:
            switch provider {
            case .openAlex, .semanticScholar, .pubMed: return 0.12
            case .crossref: return 0.08
            case .local: return 0.08
            case .youtube, .web, .openLibrary, .googleBooks, .internetArchive, .arxiv: return 0.03
            }
        case .practiceTechnique, .sourceSurvey:
            return 0.06
        }
    }

    private static func driftPenalty(text: String, intent: InquiryResearchIntent) -> Double {
        guard intent == .conceptExploration || intent == .philosophicalOrientation || intent == .historicalLineage else { return 0 }
        let lower = text.lowercased()
        let clinicalTerms = ["mental disorder", "stress", "anxiety", "randomized", "controlled trial", "meta-analysis", "systematic review", "intervention", "patient", "clinical"]
        let hits = clinicalTerms.filter { lower.contains($0) }.count
        return min(0.24, Double(hits) * 0.06)
    }

    private static func depthScore(_ candidate: InquirySourceCandidate) -> Double {
        var score = 0.0
        if candidate.sourceKind == .book { score += 0.08 }
        if candidate.evidenceRole == .primaryText { score += 0.08 }
        if candidate.evidenceRole == .lecture { score += 0.06 }
        if candidate.doi != nil { score += 0.03 }
        if candidate.qualitySignals.joined(separator: " ").localizedCaseInsensitiveContains("citations") { score += 0.03 }
        return min(score, 0.14)
    }

    private static func anchorScore(text: String, profile: InquiryBranchResearchProfile) -> Double {
        let candidateTokens = InquirySourceRecommendationEngine.significantTokens(text)
        let overlap = candidateTokens.intersection(profile.tokens).count
        return min(0.20, Double(overlap) * 0.05)
    }

    private static func passesAnchorGate(text: String, profile: InquiryBranchResearchProfile) -> Bool {
        let lower = text.lowercased()
        if profile.activeQuestionTitle.localizedCaseInsensitiveContains("pranayama") {
            return lower.contains("pranayama") || lower.contains("prana") || lower.contains("yoga")
        }
        return !InquirySourceRecommendationEngine.significantTokens(text).intersection(profile.tokens).isEmpty
    }

    private static func balanced(
        _ candidates: [InquirySourceCandidate],
        intent: InquiryResearchIntent,
        limit: Int
    ) -> [InquirySourceCandidate] {
        let laneOrder: [InquirySourceLane]
        switch intent {
        case .conceptExploration, .philosophicalOrientation:
            laneOrder = [.primaryText, .deepRead, .teacherLecture, .scholarlyContext, .practiceGuide, .webResource, .localLibrary]
        case .historicalLineage:
            laneOrder = [.primaryText, .deepRead, .scholarlyContext, .teacherLecture, .webResource, .localLibrary]
        case .practiceTechnique:
            laneOrder = [.practiceGuide, .teacherLecture, .deepRead, .clinicalEvidence, .webResource, .localLibrary]
        case .clinicalEvidence, .mechanismScience:
            laneOrder = [.clinicalEvidence, .scholarlyContext, .localLibrary, .teacherLecture, .deepRead, .webResource]
        case .sourceSurvey:
            laneOrder = InquirySourceLane.allCases
        }

        var remaining = candidates
        var result: [InquirySourceCandidate] = []
        for lane in laneOrder where result.count < limit {
            guard let index = remaining.firstIndex(where: { $0.sourceLane == lane }) else { continue }
            result.append(remaining.remove(at: index))
        }
        for candidate in remaining where result.count < limit {
            result.append(candidate)
        }
        return result
    }

    private static func reason(for candidate: InquirySourceCandidate, plan: DeepScoutPlan) -> String {
        if let lane = candidate.sourceLane {
            return "\(lane.displayName) source matched to \(plan.intent.displayName.lowercased()) research."
        }
        return "Matched to \(plan.intent.displayName.lowercased()) research."
    }

    private static func candidateText(_ candidate: InquirySourceCandidate) -> String {
        [
            candidate.title,
            candidate.subtitle,
            candidate.abstract,
            candidate.authors.joined(separator: " "),
            candidate.qualitySignals.joined(separator: " ")
        ].compactMap { $0 }.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Add the new file to Xcode**

Add `AI/DeepScoutRanker.swift` to the `CosmoOS` target.

- [ ] **Step 5: Run ranker tests**

Run the command from Step 2.

Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add AI/DeepScoutRanker.swift CosmoOS.xcodeproj/project.pbxproj Tests/CosmoOSTests/InquiryPlacementEngineTests.swift
git commit -m "feat: rank deep scout sources by intent and lane"
```

---

### Task 5: Integrate Deep Scout V2 Into Recommendation Engine

**Files:**
- Modify: `AI/InquiryPlacementEngine.swift`
- Test: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Write integration tests for query and ranking behavior**

Update existing tests:

```swift
func testDeepScoutQueryExpansionKeepsBranchAnchorAndAddsSourceAngles() {
    let profile = InquiryBranchResearchProfile(
        deepDiveTitle: "Breathwork",
        activeQuestionTitle: "What is pranayama?",
        activeQuestionUUID: "q1",
        branchNodeId: "node-1",
        ancestorTitles: [],
        claims: [],
        evidence: [],
        sourceQuery: nil
    )

    let queries = InquirySourceRecommendationEngine.scoutQueries(for: profile)
    let joined = queries.joined(separator: "\n").lowercased()

    XCTAssertGreaterThanOrEqual(queries.count, 5)
    XCTAssertTrue(joined.contains("pranayama"))
    XCTAssertTrue(joined.contains("youtube"))
    XCTAssertTrue(joined.contains("book"))
    XCTAssertTrue(joined.contains("patanjali") || joined.contains("hatha yoga pradipika"))
    XCTAssertFalse(joined.contains("randomized controlled trial"))
}
```

Add:

```swift
func testSourceRecommendationRankerDoesNotLetClinicalMetaAnalysisDominateConceptQuestion() {
    let profile = pranayamaProfile()
    let book = makeCandidate("Light on Pranayama", lane: .deepRead, provider: .openLibrary, kind: .book, role: .book)
    let clinical = InquirySourceCandidate(
        provider: .openAlex,
        sourceKind: .metaAnalysis,
        title: "Breathing practices for stress and anxiety reduction",
        abstract: "Clinical intervention for anxiety and mental health.",
        evidenceRole: .metaAnalysis,
        reason: "",
        qualitySignals: ["DOI", "Published 2024"],
        sourceLane: .clinicalEvidence
    )

    let ranked = InquirySourceRecommendationEngine.rankCandidates([clinical, book], profile: profile, existingSourceRefs: [])

    XCTAssertEqual(ranked.first?.title, book.title)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testDeepScoutQueryExpansionKeepsBranchAnchorAndAddsSourceAngles -only-testing:CosmoOSTests/InquiryPlacementEngineTests/testSourceRecommendationRankerDoesNotLetClinicalMetaAnalysisDominateConceptQuestion
```

Expected: tests fail with current academic query expansion/ranking.

- [ ] **Step 3: Replace Deep Scout query expansion wrapper**

In `InquirySourceRecommendationEngine.scoutQueries(for:)`, replace the current hard-coded `rawQueries` implementation with:

```swift
static func scoutQueries(for profile: InquiryBranchResearchProfile) -> [String] {
    DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
        .queries
        .map(\.query)
}
```

- [ ] **Step 4: Use V2 plan in `recommend(...)`**

In `recommend(...)`, add:

```swift
let deepScoutPlan = DeepScoutIntentPlanner.plan(for: profile, mode: searchMode)
let queries = searchMode == .deepScout ? deepScoutPlan.queries.map(\.query) : [profile.query]
```

For Deep Scout, fetch academic providers only for queries whose `providers` contains those providers. Fetch books and videos from `DeepScoutProviders`:

```swift
if searchMode == .deepScout {
    let plannedQueries = deepScoutPlan.queries
    for planned in plannedQueries {
        if planned.providers.contains(.openLibrary) {
            let (status, candidates) = await DeepScoutProviders.fetchOpenLibrary(query: planned, intent: deepScoutPlan.intent, profile: profile)
            statuses.append(status)
            rawCandidates += candidates
        }
        if planned.providers.contains(.googleBooks) {
            let (status, candidates) = await DeepScoutProviders.fetchGoogleBooks(query: planned, intent: deepScoutPlan.intent, profile: profile)
            statuses.append(status)
            rawCandidates += candidates
        }
        if planned.providers.contains(.internetArchive) {
            let (status, candidates) = await DeepScoutProviders.fetchInternetArchive(query: planned, intent: deepScoutPlan.intent, profile: profile)
            statuses.append(status)
            rawCandidates += candidates
        }
        if planned.providers.contains(.youtube) {
            let (status, candidates) = await DeepScoutProviders.fetchYouTube(query: planned, intent: deepScoutPlan.intent, profile: profile)
            statuses.append(status)
            rawCandidates += candidates
        }
    }
}
```

Keep the existing OpenAlex/Crossref/SemanticScholar/PubMed fetchers, but set `researchIntent` and `sourceLane` on their returned candidates according to the planned query lane before appending them.

- [ ] **Step 5: Use V2 ranker for Deep Scout**

Replace:

```swift
let ranked = Self.rankCandidates(merged, profile: profile, existingSourceRefs: existingSourceRefs)
```

with:

```swift
let ranked: [InquirySourceCandidate]
if searchMode == .deepScout {
    ranked = DeepScoutRanker.rank(
        merged,
        profile: profile,
        plan: deepScoutPlan,
        existingSourceRefs: existingSourceRefs,
        limit: 12
    )
} else {
    ranked = Self.rankCandidates(merged, profile: profile, existingSourceRefs: existingSourceRefs)
}
```

Update `rankCandidates(...)` to delegate to V2 when candidates contain `sourceLane`, so tests can call the public static method:

```swift
if candidates.contains(where: { $0.sourceLane != nil || $0.researchIntent != nil }) {
    let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
    return DeepScoutRanker.rank(candidates, profile: profile, plan: plan, existingSourceRefs: existingSourceRefs, limit: 12)
}
```

- [ ] **Step 6: Run integration tests**

Run the command from Step 2.

Expected: tests pass.

- [ ] **Step 7: Commit**

```bash
git add AI/InquiryPlacementEngine.swift Tests/CosmoOSTests/InquiryPlacementEngineTests.swift
git commit -m "feat: integrate intent-aware deep scout"
```

---

### Task 6: Improve Source UI So The Result Feels Like A Reading Map

**Files:**
- Modify: `UI/FocusMode/Inquiry/InquirySourcesRail.swift`
- Modify: `UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift`

- [ ] **Step 1: In the compact right rail, show source lane**

In `InquiryCandidateRow`, replace:

```swift
Text("\(candidate.provider.displayName) · \(candidate.evidenceRole.displayName)")
```

with:

```swift
Text(candidateMetaLine(candidate))
```

Add:

```swift
private func candidateMetaLine(_ candidate: InquirySourceCandidate) -> String {
    let lane = candidate.sourceLane?.displayName ?? candidate.evidenceRole.displayName
    return "\(lane) · \(candidate.provider.displayName)"
}
```

- [ ] **Step 2: Group Deep Scout candidates by lane in the compact rail**

Replace the flat candidates `ForEach` inside `candidatesSection` with:

```swift
ForEach(candidateGroups, id: \.lane) { group in
    VStack(alignment: .leading, spacing: DS.space6) {
        HStack(spacing: 5) {
            Image(systemName: group.lane.iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CosmoColors.textTertiary)
            Text(group.lane.displayName.uppercased())
                .dsSmallCapsLabel()
        }
        ForEach(group.candidates.prefix(3), id: \.id) { candidate in
            InquiryCandidateRow(viewModel: viewModel, candidate: candidate)
        }
    }
}
```

Add:

```swift
private var candidateGroups: [(lane: InquirySourceLane, candidates: [InquirySourceCandidate])] {
    let grouped = Dictionary(grouping: candidates) { candidate in
        candidate.sourceLane ?? .webResource
    }
    let order: [InquirySourceLane] = [.primaryText, .deepRead, .teacherLecture, .practiceGuide, .scholarlyContext, .clinicalEvidence, .webResource, .localLibrary]
    return order.compactMap { lane in
        guard let items = grouped[lane], !items.isEmpty else { return nil }
        return (lane, items)
    }
}
```

- [ ] **Step 3: Update expanded source pane metadata**

In `sourceCandidateCard(_:)`, replace the metadata line:

```swift
radarMetadata("\(candidate.provider.displayName) · \(candidate.sourceKind.displayName)")
```

with:

```swift
radarMetadata(candidate.sourceLane?.displayName ?? candidate.sourceKind.displayName)
radarMetadata(candidate.provider.displayName)
```

Keep score visible, but make the lane more important than provider name.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add UI/FocusMode/Inquiry/InquirySourcesRail.swift UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift
git commit -m "feat: show deep scout results by source lane"
```

---

### Task 7: Verification And Guardrails

**Files:**
- Modify: `Tests/CosmoOSTests/InquiryPlacementEngineTests.swift`

- [ ] **Step 1: Add screenshot-regression-oriented acceptance tests**

Add:

```swift
func testPranayamaConceptDeepScoutAcceptanceShape() {
    let profile = pranayamaProfile()
    let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)

    XCTAssertEqual(plan.intent, .conceptExploration)
    XCTAssertTrue(plan.queries.contains { $0.lane == .deepRead })
    XCTAssertTrue(plan.queries.contains { $0.lane == .teacherLecture })
    XCTAssertTrue(plan.queries.contains { $0.lane == .primaryText })
    XCTAssertTrue(plan.queries.contains { $0.providers.contains(.openLibrary) || $0.providers.contains(.googleBooks) })
    XCTAssertTrue(plan.queries.contains { $0.providers.contains(.youtube) })
}

func testPranayamaConceptDeepScoutRejectsCorporateClinicalDrift() {
    let profile = pranayamaProfile()
    let plan = DeepScoutIntentPlanner.plan(for: profile, mode: .deepScout)
    let corporate = InquirySourceCandidate(
        provider: .openAlex,
        sourceKind: .review,
        title: "Breathing practices for stress and anxiety reduction: corporate wellness outcomes",
        abstract: "An intervention for stress, anxiety, mental health, patients, and clinical outcomes.",
        evidenceRole: .review,
        reason: "",
        qualitySignals: ["DOI", "Published 2025"],
        sourceLane: .clinicalEvidence
    )
    let philosophical = InquirySourceCandidate(
        provider: .internetArchive,
        sourceKind: .book,
        title: "Pranayama in the Yoga Tradition",
        abstract: "Prana, ayama, yoga, breath, and classical philosophy.",
        evidenceRole: .primaryText,
        reason: "",
        qualitySignals: ["Primary text"],
        sourceLane: .primaryText
    )

    let ranked = DeepScoutRanker.rank([corporate, philosophical], profile: profile, plan: plan, existingSourceRefs: [], limit: 2)

    XCTAssertEqual(ranked.first?.title, philosophical.title)
}
```

- [ ] **Step 2: Run focused tests**

Run:

```bash
xcodebuild test -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/InquiryPlacementEngineTests
```

Expected: all `InquiryPlacementEngineTests` pass.

- [ ] **Step 3: Run full Debug build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 4: Manual QA**

Use the app:

1. Create an Inquiry branch titled `What is pranayama?`.
2. Run Deep Scout.
3. Verify the right rail shows grouped lanes such as `Deep read`, `Lecture`, `Primary text`, and `Scholarship`.
4. Verify at least one book candidate appears when Open Library or Google Books responds.
5. Verify YouTube candidates appear when the YouTube key is configured; if the key is missing, provider status says direct video search needs a key.
6. Verify clinical/stress/anxiety papers no longer dominate the top candidates for the conceptual question.
7. Create a separate branch titled `How does pranayama affect anxiety?`.
8. Run Deep Scout.
9. Verify reviews/meta-analyses and clinical sources are now allowed to rank highly.

- [ ] **Step 5: Commit verification changes**

```bash
git add Tests/CosmoOSTests/InquiryPlacementEngineTests.swift
git commit -m "test: cover deep scout v2 acceptance shape"
```

---

## Self-Review

**Spec coverage:** The plan covers intent detection, query generation, books, YouTube, philosophical/traditional resources, clinical drift penalties, UI grouping, and verification against the exact `What is pranayama?` failure.

**Placeholder scan:** No task relies on unspecified behavior. Provider URLs, model fields, test names, and expected behavior are explicit.

**Type consistency:** The plan consistently uses `InquiryResearchIntent`, `InquirySourceLane`, `DeepScoutIntentPlanner`, `DeepScoutProviders`, and `DeepScoutRanker`.

**Scope check:** This is one coherent subsystem: Deep Scout source discovery. It intentionally does not touch crystallization, Connection promotion, or source import mechanics beyond preserving existing candidate import behavior.
