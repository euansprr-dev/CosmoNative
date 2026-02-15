// CosmoOS/UI/FocusMode/SwipeStudy/CreatorProfileView.swift
// Full creator profile — stats, swipe grid, AI pattern analysis, editing
// February 2026

import SwiftUI

// MARK: - CreatorProfileView

struct CreatorProfileView: View {

    let creatorAtom: Atom
    let onClose: () -> Void
    let onCompare: (Atom) -> Void
    let onOpenSwipe: (Int64) -> Void

    @State private var creator: Atom
    @State private var meta: CreatorMetadata
    @State private var swipes: [Atom] = []
    @State private var isLoadingSwipes = true
    @State private var patternAnalysis: String = ""
    @State private var isAnalyzingPattern = false
    @State private var isEditing = false
    @State private var hasAppeared = false

    // Edit fields
    @State private var editHandle: String = ""
    @State private var editNiche: String = ""
    @State private var editFollowerCount: String = ""
    @State private var editNotes: String = ""
    @State private var editIsActive: Bool = true

    // Swipe filters
    @State private var narrativeFilter: NarrativeStyle?
    @State private var formatFilter: ContentFormat?

    private let gold = Color(hex: "#FFD700")

    init(creatorAtom: Atom, onClose: @escaping () -> Void, onCompare: @escaping (Atom) -> Void, onOpenSwipe: @escaping (Int64) -> Void) {
        self.creatorAtom = creatorAtom
        self.onClose = onClose
        self.onCompare = onCompare
        self.onOpenSwipe = onOpenSwipe
        let m = creatorAtom.metadataValue(as: CreatorMetadata.self) ?? CreatorMetadata()
        _creator = State(initialValue: creatorAtom)
        _meta = State(initialValue: m)
    }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().background(Color.white.opacity(0.1))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerSection
                        statsRow
                        patternSection
                        swipeGridSection
                    }
                    .padding(20)
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
        }
        .onAppear {
            loadSwipes()
            loadPatternAnalysis()
            withAnimation(ProMotionSprings.snappy) { hasAppeared = true }
        }
        .sheet(isPresented: $isEditing) {
            editSheet
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            Text(creator.title ?? "Creator")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            // Compare button
            Button {
                onCompare(creator)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11))
                    Text("Compare")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(gold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(gold.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(gold.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Edit button
            Button {
                prepareEditFields()
                isEditing = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                    Text("Edit")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(gold.opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(initialsFor(creator.title))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(gold)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(creator.title ?? "Unknown Creator")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                if let handle = meta.handle {
                    Text(handle)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }

                HStack(spacing: 8) {
                    if let platform = meta.platform {
                        platformBadge(platform)
                    }
                    if let niche = meta.niche, !niche.isEmpty {
                        Text(niche)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    if meta.isActive == true {
                        HStack(spacing: 3) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 9))
                            Text("Tracked")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(gold.opacity(0.12), in: Capsule())
                    }
                }
            }

            Spacer()

            if let followers = meta.followerCount, followers > 0 {
                VStack(spacing: 2) {
                    Text(formatFollowers(followers))
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                    Text("Followers")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 16) {
            // Total swipes
            statCard(
                value: "\(swipes.count)",
                label: "Swipes Studied",
                icon: "bolt.fill",
                color: gold
            )

            // Avg hook score
            statCard(
                value: computedAvgScore.map { String(format: "%.1f", $0) } ?? "--",
                label: "Avg Hook Score",
                icon: "chart.bar.fill",
                color: hookScoreColor(computedAvgScore)
            )

            // Top narrative
            if let topNarrative = computedTopNarrative {
                statCard(
                    value: topNarrative.displayName,
                    label: "Top Narrative",
                    icon: topNarrative.icon,
                    color: topNarrative.color
                )
            }

            // Top framework
            if let topFramework = computedTopFramework {
                statCard(
                    value: topFramework.displayName,
                    label: "Top Framework",
                    icon: "rectangle.3.group",
                    color: topFramework.color
                )
            }
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Computed Stats

    private var computedAvgScore: Double? {
        let scores = swipes.compactMap { $0.swipeAnalysis?.hookScore }
        guard !scores.isEmpty else { return meta.averageHookScore }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private var computedTopNarrative: NarrativeStyle? {
        let narratives = swipes.compactMap { $0.swipeAnalysis?.primaryNarrative }
        let counts = Dictionary(narratives.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private var computedTopFramework: SwipeFrameworkType? {
        let frameworks = swipes.compactMap { $0.swipeAnalysis?.frameworkType }
        let counts = Dictionary(frameworks.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Pattern Analysis Section

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PATTERN ANALYSIS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                if !patternAnalysis.isEmpty {
                    Button {
                        regeneratePatternAnalysis()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Refresh")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }

            if isAnalyzingPattern {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.5).tint(gold)
                    Text("Generating pattern analysis...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
            } else if !patternAnalysis.isEmpty {
                Text(patternAnalysis)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(5)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(gold.opacity(0.15), lineWidth: 1)
                    )
            } else if swipes.count >= 2 {
                Button {
                    generatePatternAnalysis()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("Generate Pattern Analysis")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(gold, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("Need at least 2 swipes to generate pattern analysis")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Swipe Grid Section

    private var swipeGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SWIPES (\(filteredSwipes.count))")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                swipeFilterMenus
            }

            if isLoadingSwipes {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                    .padding(.vertical, 40)
            } else if filteredSwipes.isEmpty {
                Text("No swipes match current filters")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filteredSwipes, id: \.uuid) { swipe in
                        compactSwipeCard(swipe)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var swipeFilterMenus: some View {
        HStack(spacing: 8) {
            // Narrative filter
            Menu {
                Button("All Narratives") { narrativeFilter = nil }
                Divider()
                ForEach(NarrativeStyle.allCases, id: \.rawValue) { style in
                    Button(style.displayName) {
                        narrativeFilter = narrativeFilter == style ? nil : style
                    }
                }
            } label: {
                narrativeFilterLabel
            }
            .menuStyle(.borderlessButton)

            // Format filter
            Menu {
                Button("All Formats") { formatFilter = nil }
                Divider()
                ForEach(ContentFormat.allCases, id: \.rawValue) { fmt in
                    Button(fmt.displayName) {
                        formatFilter = formatFilter == fmt ? nil : fmt
                    }
                }
            } label: {
                formatFilterLabel
            }
            .menuStyle(.borderlessButton)
        }
    }

    @ViewBuilder
    private var narrativeFilterLabel: some View {
        HStack(spacing: 3) {
            Text(narrativeFilter?.displayName ?? "Narrative")
                .font(.system(size: 11, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundColor(narrativeFilter != nil ? .white : .white.opacity(0.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(narrativeFilter != nil ? gold.opacity(0.2) : Color.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private var formatFilterLabel: some View {
        HStack(spacing: 3) {
            Text(formatFilter?.displayName ?? "Format")
                .font(.system(size: 11, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundColor(formatFilter != nil ? .white : .white.opacity(0.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(formatFilter != nil ? gold.opacity(0.2) : Color.white.opacity(0.06))
        )
    }

    private var filteredSwipes: [Atom] {
        var items = swipes
        if let nf = narrativeFilter {
            items = items.filter { $0.swipeAnalysis?.primaryNarrative == nf }
        }
        if let ff = formatFilter {
            items = items.filter { $0.swipeAnalysis?.swipeContentFormat == ff }
        }
        return items
    }

    @ViewBuilder
    private func compactSwipeCard(_ swipe: Atom) -> some View {
        let analysis = swipe.swipeAnalysis
        VStack(alignment: .leading, spacing: 6) {
            Text(swipe.title ?? "Untitled")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)

            if let hook = analysis?.hookText {
                Text(hook)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if let hookType = analysis?.hookType {
                    HStack(spacing: 3) {
                        Image(systemName: hookType.iconName)
                            .font(.system(size: 8))
                        Text(hookType.displayName)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(hookType.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(hookType.color.opacity(0.15), in: Capsule())
                }

                Spacer()

                if let score = analysis?.hookScore {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(hookScoreColor(score))
                }
            }
        }
        .padding(10)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onTapGesture {
            if let entityId = swipe.id {
                onOpenSwipe(entityId)
            }
        }
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Creator")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Cancel") { isEditing = false }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 12) {
                editField("Handle", text: $editHandle)
                editField("Niche", text: $editNiche)
                editField("Follower Count", text: $editFollowerCount)

                Toggle(isOn: $editIsActive) {
                    Text("Actively Tracked")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
                .toggleStyle(.switch)
                .tint(gold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                    TextEditor(text: $editNotes)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                        .scrollContentBackground(.hidden)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
            }

            HStack {
                Spacer()
                Button {
                    saveEdit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Save")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(gold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Color(hex: "#0A0A0F"))
    }

    private func editField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    // MARK: - Data Loading

    private func loadSwipes() {
        Task {
            isLoadingSwipes = true
            let all = try? await AtomRepository.shared.fetchSwipesByTaxonomy(creatorUUID: creator.uuid)
            swipes = all ?? []
            isLoadingSwipes = false

            // Recalculate and persist aggregated stats
            await recalculateCreatorStats()
        }
    }

    private func loadPatternAnalysis() {
        // Check if already cached on atom body
        if let cached = creator.body, !cached.isEmpty {
            patternAnalysis = cached
        }
    }

    private func generatePatternAnalysis() {
        guard swipes.count >= 2 else { return }
        isAnalyzingPattern = true

        Task {
            let prompt = buildPatternPrompt()
            do {
                let result = try await ResearchService.shared.analyzeContent(prompt: prompt)
                patternAnalysis = result

                // Cache on atom body
                var updated = creator
                updated.body = result
                try? await AtomRepository.shared.update(updated)
                creator = updated
            } catch {
                patternAnalysis = "Pattern analysis unavailable. Ensure your API key is configured."
            }
            isAnalyzingPattern = false
        }
    }

    private func regeneratePatternAnalysis() {
        patternAnalysis = ""
        generatePatternAnalysis()
    }

    private func buildPatternPrompt() -> String {
        let creatorName = creator.title ?? "this creator"
        let swipeSummaries = swipes.prefix(20).enumerated().map { index, swipe -> String in
            let a = swipe.swipeAnalysis
            return """
            Swipe \(index + 1): "\(swipe.title ?? "Untitled")"
            - Hook type: \(a?.hookType?.displayName ?? "unknown")
            - Hook score: \(a?.hookScore.map { String(format: "%.1f", $0) } ?? "N/A")
            - Framework: \(a?.frameworkType?.displayName ?? "unknown")
            - Narrative: \(a?.primaryNarrative?.displayName ?? "unknown")
            - Dominant emotion: \(a?.dominantEmotion?.displayName ?? "unknown")
            - Persuasion: \(a?.persuasionTechniques?.map(\.type.displayName).joined(separator: ", ") ?? "none")
            """
        }.joined(separator: "\n\n")

        return """
        You are a content strategy analyst. Analyze the following swipe files from \(creatorName) and identify what makes this creator effective.

        \(swipeSummaries)

        Provide a concise strategic summary (3-5 paragraphs) covering:
        1. Their signature hook patterns and what makes them work
        2. Preferred frameworks and structural choices
        3. Emotional manipulation patterns (which emotions they target and when)
        4. Persuasion technique stack (which combinations they rely on)
        5. Actionable takeaways: what can be learned from this creator

        Be specific and reference their actual content patterns. Write in a direct, analytical style.
        """
    }

    private func recalculateCreatorStats() async {
        let scores = swipes.compactMap { $0.swipeAnalysis?.hookScore }
        let avgScore = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)

        let narrativeCounts = Dictionary(
            swipes.compactMap { $0.swipeAnalysis?.primaryNarrative }.map { ($0.rawValue, 1) },
            uniquingKeysWith: +
        )
        let topNarratives = narrativeCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        let formatCounts = Dictionary(
            swipes.compactMap { $0.swipeAnalysis?.swipeContentFormat }.map { ($0.rawValue, 1) },
            uniquingKeysWith: +
        )
        let topFormats = formatCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        var updatedMeta = meta
        updatedMeta.swipeCount = swipes.count
        updatedMeta.averageHookScore = avgScore
        updatedMeta.topNarratives = topNarratives.isEmpty ? nil : Array(topNarratives)
        updatedMeta.topFormats = topFormats.isEmpty ? nil : Array(topFormats)

        meta = updatedMeta
        var updatedCreator = creator.withMetadata(updatedMeta)
        try? await AtomRepository.shared.update(updatedCreator)
        creator = updatedCreator
    }

    // MARK: - Edit Helpers

    private func prepareEditFields() {
        editHandle = meta.handle ?? ""
        editNiche = meta.niche ?? ""
        editFollowerCount = meta.followerCount.map { "\($0)" } ?? ""
        editNotes = meta.notes ?? ""
        editIsActive = meta.isActive ?? true
    }

    private func saveEdit() {
        var updatedMeta = meta
        updatedMeta.handle = editHandle.isEmpty ? nil : editHandle
        updatedMeta.niche = editNiche.isEmpty ? nil : editNiche
        updatedMeta.followerCount = Int(editFollowerCount)
        updatedMeta.notes = editNotes.isEmpty ? nil : editNotes
        updatedMeta.isActive = editIsActive

        meta = updatedMeta
        var updatedCreator = creator.withMetadata(updatedMeta)

        Task {
            try? await AtomRepository.shared.update(updatedCreator)
            creator = updatedCreator
        }

        isEditing = false
    }

    // MARK: - Subviews

    private func platformBadge(_ platform: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: platformIconFor(platform))
                .font(.system(size: 10))
            Text(platformNameFor(platform))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    // MARK: - Helpers

    private func initialsFor(_ name: String?) -> String {
        guard let name = name, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func hookScoreColor(_ score: Double?) -> Color {
        guard let score = score else { return Color(hex: "#64748B") }
        if score >= 8.0 { return Color(hex: "#10B981") }
        if score >= 5.0 { return Color(hex: "#3B82F6") }
        return Color(hex: "#64748B")
    }

    private func formatFollowers(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func platformIconFor(_ raw: String) -> String {
        switch raw {
        case "youtube": return "play.rectangle.fill"
        case "instagram": return "camera.fill"
        case "x", "twitter": return "bubble.left.fill"
        case "threads": return "at"
        case "tiktok": return "music.note"
        default: return "globe"
        }
    }

    private func platformNameFor(_ raw: String) -> String {
        switch raw {
        case "youtube": return "YouTube"
        case "instagram": return "Instagram"
        case "x", "twitter": return "X"
        case "threads": return "Threads"
        case "tiktok": return "TikTok"
        default: return raw.capitalized
        }
    }
}
