# Main Swipe File Discoverer and Creators Design

Date: 2026-05-29
Status: Draft for user review
Scope: Existing main Swipe File sidebar surface only: Discoverer tab, Creators tab, cross-platform data linking, and save-to-board actions from those tabs.

## Goal

Make the existing main Swipe File feel like a high-performing content intelligence workspace by building the inside UI and data system for Discoverer and Creators. All Swipes remains the canonical saved-swipe library. Discoverer and Creators bring in cross-platform posts, rank them by performance, expose transcripts where possible, and let the user save posts to existing custom boards without duplicating the saved-swipe model.

## Current Project Context

The repo already has the pieces this should build on:

- Main navigation and sidebar structure live under `Navigation/MainView.swift` and `Canvas/UnifiedSidebar/UnifiedSidebar.swift`.
- Saved swipes are `.research` atoms where `researchMetadata.isSwipeFile == true`.
- `SwipeFile/SwipeAnalysis.swift` defines `SwipeGalleryItem`, engagement fields, platform display helpers, and `Atom.toSwipeGalleryItem()`.
- `SwipeFile/SwipeFileEngine.swift` captures and persists swipe atoms.
- `SwipeFile/SwipeProcessingService.swift` processes transcripts/media after capture.
- `UI/FocusMode/SwipeStudy/SwipeStudyFocusModeView.swift` is the existing per-swipe detail/study surface.
- `UI/FocusMode/SwipeStudy/CreatorListView.swift`, `CreatorProfileView.swift`, and `CreatorImportSheet.swift` already cover parts of creator import and creator browsing.
- `SwipeFile/Instagram/ApifyInstagramProvider.swift` and `CreatorImportEngine.swift` already prove the provider pattern for Instagram creator catalogs.
- `Data/Services/SocialSyncService.swift` contains platform-specific official API work, but it is mainly account-sync oriented and not sufficient for broad public discovery.

This design should consolidate and extend these pieces rather than introducing a separate swipe-file product or Command-K-only flow.

## Non-Goals

- Do not redesign Command-K Swipe Gallery.
- Do not replace the existing All Swipes tab.
- Do not make a new sidebar destination for Swipe File.
- Do not force every discovered external post into the permanent swipe library.
- Do not rely on unofficial HTML scraping inside SwiftUI views.
- Do not promise complete historical coverage when a platform/provider only returns a bounded catalog.

## Product Model

### All Swipes

All Swipes remains the user's saved source of truth. A post appears here only after it has been saved as a swipe atom. Discoverer and Creators can save posts into All Swipes, optionally with board membership, but they do not change what All Swipes means.

### Discoverer

Discoverer is a cross-platform discovery feed for high-performing public posts. It answers: "What is currently outperforming in this topic, platform, language, follower range, and time window?"

Required filters:

- platform: Instagram, YouTube, LinkedIn, X, Substack, TikTok, and all-platforms
- language
- creator follower count range
- outlier score range
- posted window: week, month, three months, year, all time
- content pillar/category
- query text

Required post card data:

- platform badge
- creator avatar/name/handle
- post preview: media thumbnail/video poster or text preview
- published date or age
- views where available
- likes
- comments
- shares/reposts where available
- outlier score
- letter grade
- saved/unsaved state
- plus action to save to All Swipes and optionally a board

The feed should use masonry-style visual density similar to the provided references, but it must stay on-brand with CosmoOS: restrained surfaces, semantic `DS` colors, SF Symbols, compact metadata, and no marketing-page composition.

### Creators

Creators is a cross-platform creator intelligence tab. It answers: "Which creators am I tracking, and what are their best-performing posts across platforms?"

Required creator list behavior:

- search by handle or paste profile URL
- add creator to tracked creators
- show platform, avatar, display name, handle, bio, follower count, post count, and last refresh
- filter creators by platform, niche/category, follower range, and saved status
- sort creators by name, follower count, post count, average outlier score, highest outlier score, and last refresh

Required creator profile behavior:

- show creator header with cross-platform identity when known
- fetch or refresh post catalog
- sort posts by top views, most liked, most commented, most shared/reposted, highest outlier, most recent
- filter by platform, format, posted window, saved/unsaved, and language
- save any post to All Swipes and optionally a custom board
- open a post detail modal with metrics, caption/body, transcript controls, and source link

## Provider Strategy

Use a long-term cross-platform provider foundation with adapters. The app should not bake Bright Data, Apify, YouTube, or X directly into view models.

### Recommended Provider Stack

Primary cross-platform provider:

- Bright Data Social Media APIs for broad public discovery and creator catalogs across platforms where official APIs are restricted or incomplete.

Existing/fallback provider:

- Apify for Instagram, initially reusing the existing `InstagramDataProvider` and `ApifyInstagramProvider` patterns.

Official providers where strong:

- YouTube Data API for YouTube search/video/channel metadata.
- X API for X search/timeline/public metrics when the configured access tier supports it.
- Substack RSS and available official APIs for publication posts.

Owned-account sync remains separate:

- `SocialSyncService` can continue handling connected account analytics. Discoverer/Creators should not be coupled to owned-account sync because public discovery has different permissions, rate limits, and data guarantees.

### Provider Interface

Create provider-neutral service types under `SwipeFile/Discovery/`:

- `SocialDiscoveryProvider`
- `SocialCreatorProvider`
- `SocialTranscriptProvider`
- `SocialProviderRegistry`
- `SocialProviderCapability`

Providers declare capabilities:

- supports keyword discovery
- supports creator lookup
- supports creator catalog
- supports engagement metrics
- supports view counts
- supports follower counts
- supports native transcript
- supports media download URL
- supports pagination
- supports refresh-after timestamp

The UI queries capabilities and disables unavailable filters/actions with clear empty states instead of failing late.

## Normalized Data

### Discovered Posts

Discovered posts are cached separately from saved swipe atoms. They become saved swipes only when the user saves them.

Create a normalized model:

- stable `id`
- `platform`
- `provider`
- provider post ID
- canonical URL
- title/caption/body
- media URLs and thumbnails
- author platform ID
- author handle/name/avatar
- author follower count snapshot
- published date
- detected language
- metrics snapshot: views, likes, comments, shares, saves, reposts, impressions, engagement rate
- derived metrics: outlier score, grade, velocity score
- transcript state: none, available, fetching, fetched, failed
- save state: unsaved, saved atom UUID
- raw provider payload JSON for audit/debug only

Persist discovered posts in a dedicated cache table or atom sidecar store. Do not store them as swipe atoms until saved.

### Creators

Use `.creator` atoms for tracked creators, but normalize platform identities so one creator can have multiple platform handles.

Creator metadata should store:

- display name
- bio
- avatar URL
- primary platform
- platform identities: platform, handle, profile URL, provider ID
- follower count snapshots by platform
- post count snapshots by platform
- category/niche tags
- last refresh timestamp by platform
- provider/source provenance

### Saved Swipes

When a discovered post is saved:

1. Create or update the creator atom.
2. Create a `.research` atom using existing swipe factory/capture patterns.
3. Set `isSwipeFile = true`.
4. Preserve source URL, platform, caption/body, media metadata, engagement snapshot, outlier score, and provider provenance.
5. Queue `SwipeProcessingService` for transcript/media enrichment when needed.
6. Add board membership if the user selected a board.
7. Refresh All Swipes state through existing swipe-change notifications.

## Outlier Score and Grade

Outlier score is the core ranking signal. It should be deterministic and explainable.

Use:

```text
outlierScore = postPrimaryReach / creatorBaselinePrimaryReach
```

Where:

- primary reach is views when views exist, otherwise impressions, otherwise engagement-weighted reach estimate
- creator baseline is median reach across recent comparable posts
- comparable means same creator, same platform, similar format where available, excluding the current post
- median is preferred over mean because viral posts distort averages
- when fewer than five comparable posts exist, show "insufficient baseline" and avoid overconfident grades

Letter grade:

- S: top 1 percent within comparable result set or outlier >= 20x
- A: top 5 percent or outlier >= 10x
- B: top 15 percent or outlier >= 5x
- C: above median or outlier >= 2x
- D: below median

The UI should show both the numeric multiplier and the grade. The detail modal should explain the baseline in one compact line, for example: "16x vs creator median views across 42 recent Instagram reels."

## Discoverer UI

### Layout

Use a three-band structure:

1. Header search and global filter summary.
2. Filter rail with platform, language, followers, outlier, posted window, and categories.
3. Virtualized masonry feed.

Cards should be compact and scannable:

- media-first for image/video platforms
- text-first for X, LinkedIn, and Substack
- platform icon in a consistent corner
- metrics row with icons
- outlier pill with warm swipe accent
- plus button bottom-right on hover/focus

### Interactions

Click card:

- opens post detail modal

Click plus:

- opens board picker
- default action is "Save to All Swipes"
- optional board selection adds board membership at save time

Long-click and drag:

- starts a drag payload for the discovered post
- dropping on an existing board saves it to All Swipes and adds that board membership
- if the post is already saved, dropping only adds board membership

Keyboard:

- arrow keys move card focus
- return opens detail
- `S` saves
- `B` opens board picker
- escape closes modal/picker

### Empty and Error States

No query yet:

- show suggested searches/categories, not a marketing explainer

Provider not configured:

- show required provider and settings action

Rate limited:

- show retry time and cached results if available

Partial platform failure:

- keep successful platform results visible and show a compact warning chip

## Creators UI

### Layout

Creators should use a split pattern:

- left/main: creator list or grid
- right/detail or modal: creator profile and post catalog

The existing `CreatorListView`/`CreatorProfileView` behavior can be refactored into the main tab rather than remaining only as overlays.

### Add Creator Flow

Input accepts:

- `@handle`
- full profile URL
- platform-prefixed handle, such as `youtube:@name` or `x:@name`

Resolution flow:

1. Detect platform from URL or prefix.
2. Ask provider registry for a creator lookup provider.
3. Fetch profile and show confirmation row.
4. Create/update creator atom.
5. Fetch first catalog page.
6. Cache discovered posts.
7. Show creator profile with posts sorted by highest outlier.

If platform is ambiguous, ask the user to choose a platform in a compact picker.

### Creator Profile Detail

Header:

- avatar
- display name
- handle/platform badges
- bio
- follower counts
- tracked/synced status
- refresh button

Stats:

- total tracked posts
- median views/reach
- highest outlier
- average engagement
- strongest platform

Post catalog:

- same reusable `SocialPostCard` as Discoverer
- sort menu: top views, most liked, most commented, most shared/reposted, highest outlier, most recent
- filter chips: platform, format, posted window, saved/unsaved, language

## Post Detail Modal

Use one shared detail modal for Discoverer and Creators.

Required content:

- source platform and source title/caption
- creator block
- metric strip: outlier, views, likes, comments, shares/reposts, engagement rate
- media preview or text body
- caption/body with copy button
- transcript panel
- mentions/tags if detected
- source URL/open externally
- save-to-board action

Transcript behavior:

- YouTube: prefer captions when available; fall back to existing transcript fetcher or audio transcription.
- Instagram/TikTok/short-form video: queue media extraction/transcription through existing swipe processing paths when provider gives media access.
- X/LinkedIn/Substack: treat post body/thread/article text as transcript-equivalent, with optional expansion if the provider returns a thread/article.
- If transcript is unavailable, show "No transcript available from this source" rather than an infinite spinner.

## Board Integration

This spec assumes custom boards exist in the main Swipe File experience. Discoverer and Creators need only the shared actions:

- list boards
- create board from picker
- add saved swipe UUID to board
- remove saved swipe UUID from board where supported
- accept drag payloads from discovered posts and creator posts

If implementation discovers that no durable board membership service exists, add the smallest focused board store needed for these actions without redesigning All Swipes.

Board picker behavior:

- show All Swipes as the implicit save destination
- show custom boards with counts
- allow multi-select
- provide "New Board" inline
- after save, show a short confirmation and update card saved state

## Architecture

### Feature Modules

Create or refactor toward this shape:

- `SwipeFile/Discovery/SocialDiscoveryModels.swift`
- `SwipeFile/Discovery/SocialDiscoveryProvider.swift`
- `SwipeFile/Discovery/SocialProviderRegistry.swift`
- `SwipeFile/Discovery/SocialDiscoveryService.swift`
- `SwipeFile/Discovery/SocialCreatorService.swift`
- `SwipeFile/Discovery/SocialPostCacheStore.swift`
- `SwipeFile/Discovery/SocialOutlierScorer.swift`
- `SwipeFile/Discovery/SocialPostSaveService.swift`
- `SwipeFile/Discovery/Providers/BrightDataSocialProvider.swift`
- `SwipeFile/Discovery/Providers/YouTubeDiscoveryProvider.swift`
- `SwipeFile/Discovery/Providers/XDiscoveryProvider.swift`
- `SwipeFile/Discovery/Providers/SubstackDiscoveryProvider.swift`
- `SwipeFile/Boards/SwipeBoardService.swift` only if an equivalent durable service does not already exist
- `UI/SwipeFile/MainSwipeFileView.swift` or the existing main swipe file view if already present
- `UI/SwipeFile/DiscovererTabView.swift`
- `UI/SwipeFile/CreatorsTabView.swift`
- `UI/SwipeFile/SocialPostCard.swift`
- `UI/SwipeFile/SocialPostDetailModal.swift`
- `UI/SwipeFile/SwipeBoardPicker.swift`

The implementation plan should first locate the existing main Swipe File files and adapt these names to current project structure.

### State Ownership

Use `@Observable` or `ObservableObject` stores per tab:

- `DiscovererViewModel`
- `CreatorsViewModel`
- `SocialPostDetailViewModel`

Keep provider clients and cache stores out of SwiftUI views. Views should call view-model intents like `search()`, `refreshCreator()`, `save(post:boards:)`, and `fetchTranscript(post:)`.

### Data Flow

Discoverer search:

1. User changes query/filter.
2. `DiscovererViewModel` builds `SocialDiscoveryQuery`.
3. `SocialDiscoveryService` checks cache for fresh results.
4. Provider registry fans out to capable providers.
5. Results normalize into `SocialPostSnapshot`.
6. `SocialOutlierScorer` calculates multipliers and grades.
7. Cache persists snapshots and query result IDs.
8. UI renders virtualized cards.

Creator import:

1. User enters handle/profile URL.
2. `SocialCreatorService` resolves platform identity.
3. Provider fetches profile.
4. Creator atom is created or updated.
5. Provider fetches catalog pages.
6. Posts normalize and cache.
7. Profile UI renders posts and metrics.

Save post:

1. User clicks plus, saves from modal, or drops post on board.
2. `SocialPostSaveService` checks whether canonical URL/provider ID already maps to a saved swipe.
3. If unsaved, create swipe atom and queue enrichment.
4. If board was selected, add membership.
5. Post saved state updates in Discoverer/Creators and All Swipes receives existing refresh notifications.

## Error Handling

Provider failures must include:

- platform
- provider
- failure category: configuration, auth, rate limit, not found, private/unavailable, decoding, network, quota
- retry date when known

The UI should:

- keep cached results visible when refresh fails
- show per-platform warnings rather than replacing the whole feed with an error
- explain when a metric is unavailable from the source
- preserve raw payload for debugging but never require users to inspect it

## Privacy and Compliance

- Store provider API keys in the existing API key/config system, not in source.
- Persist provider provenance for every cached post and saved swipe.
- Respect provider rate limits and refresh-after windows.
- Avoid background mass-refresh unless the user has configured providers and explicitly tracks creators.
- Do not bypass platform access controls; private or unavailable profiles should fail clearly.

## Testing

Unit tests:

- platform URL/handle resolution
- provider capability selection
- normalized post decoding for each supported platform fixture
- outlier score baseline calculation with median, insufficient baseline, and missing views
- grade assignment
- discovered post save creates a swipe atom once and deduplicates later saves
- board picker save adds board membership without duplicating swipe atoms
- creator profile update merges platform identities rather than creating duplicates

View-model tests:

- Discoverer query/filter changes produce correct service calls
- partial provider failure keeps successful results
- cached results render while refresh is pending
- creator sort/filter modes produce expected ordering
- save state updates after save-to-board

Build verification:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug test
```

Manual verification:

- Discoverer can query at least YouTube plus one managed provider-backed platform.
- Creators can add a creator by profile URL and show posts.
- A discovered post can be saved to All Swipes.
- A discovered post can be saved directly to a custom board.
- A saved post appears in All Swipes and remains visible in source Discoverer/Creators cards as saved.
- Transcript fetch succeeds where source data supports it and fails clearly where it does not.

## Acceptance Criteria

- The existing main Swipe File sidebar destination/tab structure remains intact.
- All Swipes continues to show every saved swipe and is not replaced.
- Discoverer renders real normalized cross-platform discovery results from provider-backed data.
- Discoverer supports platform, language, follower count, outlier score, and posted-window filters.
- Creators supports adding a creator by handle or profile URL.
- Creator profiles show sortable post catalogs with outlier and engagement metrics.
- Post detail modal is shared by Discoverer and Creators.
- Save-to-board works from cards and detail modal.
- Long-click/drag from Discoverer/Creators into boards saves unsaved posts first, then adds the saved swipe UUID to the target board; already-saved posts only add board membership.
- Saved discovered posts become normal swipe atoms and participate in existing Swipe Study and All Swipes behavior.
- Provider errors, rate limits, missing metrics, and missing transcripts produce useful UI states.
- The implementation has focused unit/view-model tests and the app test target passes.

## Research References

- YouTube Data API videos and statistics: https://developers.google.com/youtube/v3/docs/videos
- X API rate limits and access constraints: https://docs.x.com/x-api/fundamentals/rate-limits
- LinkedIn Posts API: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api
- TikTok Display API overview: https://developers.tiktok.com/doc/display-api-overview/
- Substack RSS support: https://support.substack.com/hc/en-us/articles/360038239391-Is-there-an-RSS-feed-for-my-publication
- Bright Data Social Media APIs: https://docs.brightdata.com/api-reference/scrapers/social-media-apis/overview
- Apify Instagram Scraper: https://apify.com/apify/instagram-scraper
