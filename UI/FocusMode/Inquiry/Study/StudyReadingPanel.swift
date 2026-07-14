// CosmoOS/UI/FocusMode/Inquiry/Study/StudyReadingPanel.swift
// The right inspector: everything worth reading — sources you added, then
// scouted candidates grouped by lane — in ONE Files-grammar list, docked
// edge-to-edge alongside the content (Apple's inspector idiom). The scout
// runs itself; the header's refresh glyph is the only manual control, and
// while a scout is live the header's count gives way to the activity line.
// Successor of InquirySourcesRail.

import SwiftUI

@MainActor
struct StudyReadingPanel: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    var isOverlay: Bool = false

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if isPresentingSearch {
                searchResultsList
            } else if visibleSources.isEmpty && candidates.isEmpty {
                teachingState
            } else {
                list
            }
            if viewModel.isRefreshingSources, !viewModel.liveProviderStatuses.isEmpty {
                scoutProgress
            }
        }
        .frame(width: StudyMetrics.panelWidth)
        .studyPanelSurface(edge: .trailing, isOverlay: isOverlay)
        .animation(ProMotionSprings.gentle, value: viewModel.isRailSearchActive)
        .task(id: viewModel.railSearchQuery) { await debouncedSearch() }
    }

    /// Results replace the list only once there's a query to answer.
    private var isPresentingSearch: Bool {
        viewModel.isRailSearchActive
            && !viewModel.railSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func debouncedSearch() async {
        guard viewModel.isRailSearchActive else { return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        await viewModel.runRailSearch()
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        Group {
            if viewModel.isRailSearchActive {
                searchHeader
            } else {
                readingHeader
            }
        }
        .padding(.leading, DS.space16)
        .padding(.trailing, DS.space10)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space10)
    }

    private var readingHeader: some View {
        HStack(spacing: DS.space6) {
            Text("READING")
                .dsSmallCapsLabel()
            Spacer()
            if let line = viewModel.sourceActivityLine {
                Text(line)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
                    .transition(.opacity)
            } else {
                Text("\(visibleSources.count + candidates.count)")
                    .font(DS.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(DS.textMuted)
            }
            searchButton
            rescoutButton
        }
        .animation(ProMotionSprings.gentle, value: viewModel.sourceActivityLine)
    }

    /// Search mode: the header row becomes the field (Mail's idiom) — the
    /// list beneath turns into live YouTube results.
    private var searchHeader: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: "magnifyingglass")
                .font(DS.caption)
                .foregroundStyle(searchFocused ? DS.accent : DS.textMuted)
                .accessibilityHidden(true)
            TextField("Search YouTube", text: $viewModel.railSearchQuery)
                .textFieldStyle(.plain)
                .font(DS.footnote)
                .focused($searchFocused)
                .onSubmit { Task { await viewModel.runRailSearch() } }
                .onExitCommand { viewModel.exitRailSearch() }
            Button {
                viewModel.exitRailSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
            .help("Close search")
            .accessibilityLabel("Close YouTube search")
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 5)
        .background(DS.glassInputFill.opacity(searchFocused ? 1 : 0.6), in: Capsule())
        .overlay(Capsule().stroke(searchFocused ? DS.focusRing : DS.borderSubtle, lineWidth: 1))
        .animation(ProMotionSprings.hover, value: searchFocused)
    }

    private var searchButton: some View {
        Button {
            viewModel.isRailSearchActive = true
            // The field mounts on the next frame — focus once it exists.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                searchFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Search YouTube for sources")
        .accessibilityLabel("Search YouTube for sources")
    }

    private var rescoutButton: some View {
        Button {
            Task { await viewModel.refreshSourceRecommendations(query: nil, mode: .deepScout) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(viewModel.isRefreshingSources ? DS.textMuted.opacity(0.4) : DS.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRefreshingSources)
        .help("Scout for new sources")
        .accessibilityLabel("Scout for new sources")
    }

    // MARK: - The one list

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !userAddedSources.isEmpty {
                    sectionHeader("ADDED BY YOU", count: userAddedSources.count)
                    rows(of: userAddedSources)
                }
                if !discoveredSources.isEmpty {
                    sectionHeader("IN THIS SESSION", count: discoveredSources.count)
                    rows(of: discoveredSources)
                }
                ForEach(candidateGroups, id: \.lane) { group in
                    sectionHeader(group.lane.displayName.uppercased(), count: group.candidates.count)
                    ForEach(Array(group.candidates.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 { rowSeparator }
                        StudyCandidatePanelRow(viewModel: viewModel, candidate: candidate)
                    }
                }
            }
            // The thinking bar floats over the panel's foot — keep the last
            // rows reachable above it.
            .padding(.bottom, StudyMetrics.panelBottomInset)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - YouTube search results

    private var searchResults: [InquirySourceCandidate] {
        viewModel.railSearchResults.filter { $0.importStatus == .candidate }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                sectionHeader("YOUTUBE", count: searchResults.count)
                if viewModel.isRailSearching && searchResults.isEmpty {
                    searchSkeleton
                } else if searchResults.isEmpty {
                    Text("No videos found — try different words.")
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                        .padding(.horizontal, DS.space16)
                        .padding(.vertical, DS.space12)
                } else {
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 { rowSeparator }
                        StudyCandidatePanelRow(viewModel: viewModel, candidate: candidate)
                    }
                }
            }
            .padding(.bottom, StudyMetrics.panelBottomInset)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    /// Result-shaped placeholder rows while the first results are in flight.
    private var searchSkeleton: some View {
        ForEach(0..<5, id: \.self) { index in
            HStack(alignment: .top, spacing: DS.space8) {
                Circle()
                    .fill(DS.glassSectionFill)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(DS.glassSectionFill)
                        .frame(width: index.isMultiple(of: 2) ? 190 : 150, height: 10)
                    Capsule()
                        .fill(DS.glassSectionFill)
                        .frame(width: 110, height: 8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
        }
        .accessibilityHidden(true)
    }

    private func rows(of sources: [InquirySourceRef]) -> some View {
        ForEach(Array(sources.enumerated()), id: \.element.sourceUUID) { index, ref in
            if index > 0 { rowSeparator }
            StudySourceRow(viewModel: viewModel, ref: ref)
        }
    }

    private func sectionHeader(_ label: String, count: Int) -> some View {
        HStack(spacing: DS.space6) {
            Text(label)
                .font(DS.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text("\(count)")
                .font(DS.caption2)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space12)
        .padding(.bottom, DS.space6)
    }

    private var rowSeparator: some View {
        Divider()
            .overlay(DS.glassBorder)
            .padding(.leading, 40)
    }

    private var teachingState: some View {
        VStack {
            Text("Scout is looking for lectures, podcasts, and books — or paste a URL in the bar below.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.space16)
                .padding(.vertical, DS.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
    }

    // MARK: - Scout progress (flat footer)

    private var scoutProgress: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(viewModel.liveProviderStatuses.sorted { $0.provider.displayName < $1.provider.displayName }) { status in
                HStack(spacing: DS.space6) {
                    statusIcon(status.state)
                    Text(status.provider.displayName)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                    Spacer()
                    if status.state == .succeeded, status.count > 0 {
                        Text("\(status.count)")
                            .font(DS.caption2)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(DS.textMuted)
                    }
                }
                // The warn icon must explain itself — a bare orange mark next
                // to "Semantic Scholar" said nothing about what went wrong.
                .help(statusHelp(status))
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space8)
        .background(DS.glassSectionFill)
        .animation(ProMotionSprings.gentle, value: viewModel.liveProviderStatuses)
    }

    private func statusHelp(_ status: InquiryProviderStatus) -> String {
        switch status.state {
        case .idle, .loading:
            return "\(status.provider.displayName) — searching"
        case .succeeded:
            return "\(status.provider.displayName) — \(status.count) result\(status.count == 1 ? "" : "s")"
        case .failed:
            return "\(status.provider.displayName) didn't respond this run — its lane is skipped, everything else still ranks"
        case .rateLimited:
            return "\(status.provider.displayName) rate-limited this run — try Scout again in a minute"
        case .missingKey:
            return "\(status.provider.displayName) needs an API key in Settings"
        }
    }

    @ViewBuilder
    private func statusIcon(_ state: InquiryProviderStatus.State) -> some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.55)
                .frame(width: 10, height: 10)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(DS.green)
                .accessibilityLabel("Done")
        case .failed, .rateLimited:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 9))
                .foregroundStyle(DS.orange)
                .accessibilityLabel("Failed")
        case .missingKey:
            Image(systemName: "key.slash")
                .font(.system(size: 9))
                .foregroundStyle(DS.textMuted)
                .accessibilityLabel("Missing API key")
        }
    }

    // MARK: - Data

    private var visibleSources: [InquirySourceRef] {
        viewModel.structured.sourceRefs
            .filter { $0.status != .archived && $0.status != .deleted }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private var userAddedSources: [InquirySourceRef] {
        visibleSources.filter { $0.addedByUser == true }
    }

    private var discoveredSources: [InquirySourceRef] {
        visibleSources.filter { $0.addedByUser != true }
    }

    private var candidates: [InquirySourceCandidate] {
        viewModel.activeSourceCandidates.filter { $0.importStatus == .candidate }
    }

    private var candidateGroups: [(lane: InquirySourceLane, candidates: [InquirySourceCandidate])] {
        let limited = Array(candidates.prefix(20))
        let grouped = Dictionary(grouping: limited) { candidate in
            candidate.sourceLane ?? .webResource
        }
        let laneOrder: [InquirySourceLane] = [
            .localLibrary, .teacherLecture, .deepRead, .primaryText,
            .practiceGuide, .scholarlyContext, .clinicalEvidence, .webResource
        ]
        return laneOrder.compactMap { lane in
            guard let group = grouped[lane], !group.isEmpty else { return nil }
            return (lane, group)
        }
    }
}

// MARK: - Source row

@MainActor
private struct StudySourceRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let ref: InquirySourceRef

    @State private var isHovered = false

    var body: some View {
        Button {
            viewModel.openReader(forSourceRef: ref)
        } label: {
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: iconName)
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.title)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(metaLine)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
            .background(isHovered ? DS.surfaceElevated.opacity(0.6) : .clear)
            .offset(x: isHovered ? 2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel("Open source: \(ref.title)")
    }

    private var iconName: String {
        if let url = ref.url, !url.isEmpty { return "globe" }
        switch ref.sourceType {
        case "video", "youtube": return "play.rectangle"
        case "book": return "book.closed"
        case "note": return "note.text"
        default: return "doc.text"
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let domain = ref.domain, !domain.isEmpty { parts.append(domain) }
        if ref.extractCount > 0 {
            parts.append("\(ref.extractCount) extracts")
        } else if ref.noteCount > 0 {
            parts.append("\(ref.noteCount) notes")
        }
        if parts.isEmpty { parts.append(ref.status.displayName) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Candidate row

@MainActor
private struct StudyCandidatePanelRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let candidate: InquirySourceCandidate

    @State private var isHovered = false

    var body: some View {
        Button {
            Task { await viewModel.importSourceCandidate(candidate) }
        } label: {
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: (candidate.sourceLane ?? .webResource).iconName)
                    .font(DS.caption)
                    .foregroundStyle(isHovered ? DS.accent : DS.textMuted)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(metaLine)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.circle")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space8)
            .background(isHovered ? DS.surfaceElevated.opacity(0.6) : .clear)
            .offset(x: isHovered ? 2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .onDrag {
            guard let url = candidate.url, let nsURL = NSURL(string: url) else {
                return NSItemProvider()
            }
            return NSItemProvider(object: nsURL)
        }
        .contextMenu {
            Button("Import") {
                Task { await viewModel.importSourceCandidate(candidate) }
            }
            Button("Queue for later") {
                viewModel.queueSourceCandidate(candidate)
            }
            Divider()
            Button("Not useful", role: .destructive) {
                viewModel.dismissSourceCandidate(candidate)
            }
        }
        .help(helpLine)
        .accessibilityLabel("Import candidate: \(candidate.title)")
    }

    /// The ranker's reason belongs in the tooltip: rendered on every row,
    /// "Mentions breathing, breathwork and fills a review role." ×12 read as
    /// an LLM wall, not a library.
    private var helpLine: String {
        if !candidate.reason.isEmpty && !candidate.reason.hasPrefix("Deep Scout") {
            return "\(candidate.reason) — click to import"
        }
        return "Import into this session"
    }

    private var metaLine: String {
        // Honest fields only: creator/subtitle, then stats or provider.
        var parts: [String] = []
        if let creator = DeepScoutTasteStore.creatorName(for: candidate) {
            parts.append(creator)
        } else if let subtitle = candidate.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        if statSignals.isEmpty {
            parts.append(candidate.provider.displayName)
        } else {
            parts.append(contentsOf: statSignals)
        }
        return parts.joined(separator: " · ")
    }

    /// Duration and view-count signals ("12 min", "1.2M views", "12:34") —
    /// the honest meta for rows whose reason is just the generic Scout line.
    private var statSignals: [String] {
        candidate.qualitySignals.filter { signal in
            signal.hasSuffix(" min") || signal.hasSuffix("views")
                || (!signal.isEmpty && signal.allSatisfy { $0.isNumber || $0 == ":" || $0 == "," })
        }
    }
}
