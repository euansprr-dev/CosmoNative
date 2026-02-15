// CosmoOS/UI/FocusMode/Content/PostCreationPhaseView.swift
// Views for post-creation pipeline phases (Scheduled, Published, Analyzing, Archived)
// February 2026

import SwiftUI

// MARK: - Post Creation Phase View

/// Router view for phases 4-7 of the content pipeline.
/// Displayed when the content is past the creation phases (ideation-polish).
struct PostCreationPhaseView: View {
    let phase: ContentPhase
    let atom: Atom
    @Binding var state: ContentFocusModeState
    var onAdvancePhase: ((ContentPhase) -> Void)? = nil

    @State private var scheduledDate: Date = Date().addingTimeInterval(3600)
    @State private var postURL: String = ""
    @State private var impressionsText: String = ""
    @State private var reachText: String = ""
    @State private var likesText: String = ""
    @State private var commentsText: String = ""
    @State private var sharesText: String = ""
    @State private var savesText: String = ""
    @State private var isSavingPerformance: Bool = false

    private let accentColor = CosmoMentionColors.content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                phaseBody
            }
            .frame(maxWidth: 700)
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch phase {
        case .scheduled: scheduledView
        case .published: publishedView
        case .analyzing: analyzingView
        case .archived: archivedView
        default: EmptyView()
        }
    }

    // MARK: - Scheduled View

    @ViewBuilder
    private var scheduledView: some View {
        phaseHeader(title: "Schedule & Publish", icon: "calendar.badge.clock")

        // Platform confirmation
        VStack(alignment: .leading, spacing: 10) {
            Text("PLATFORM")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.35))

            platformPills
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Date/time picker
        VStack(alignment: .leading, spacing: 12) {
            Text("SCHEDULE FOR")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.35))

            DatePicker(
                "",
                selection: $scheduledDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .colorScheme(.dark)
            .padding(16)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }

        // Predicted reach
        scheduledPredictionCard

        // Action buttons
        HStack(spacing: 12) {
            Button {
                // Schedule is informational — publish when ready
                publishNow()
            } label: {
                scheduledButtonLabel(text: "Schedule", icon: "calendar.badge.clock", isPrimary: false)
            }
            .buttonStyle(.plain)

            Button {
                publishNow()
            } label: {
                scheduledButtonLabel(text: "Publish Now", icon: "paperplane.fill", isPrimary: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func scheduledButtonLabel(text: String, icon: String, isPrimary: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 14, weight: isPrimary ? .semibold : .medium))
        }
        .foregroundColor(isPrimary ? .white : .white.opacity(0.8))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            isPrimary ? AnyShapeStyle(accentColor) : AnyShapeStyle(Color.white.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var scheduledPredictionCard: some View {
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PREDICTED REACH")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.35))

                if let predicted = metadata?.predictedReach {
                    Text(formatNumber(predicted))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                } else {
                    Text("--")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            Spacer()

            if let engagement = metadata?.predictedEngagement {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("EST. ENGAGEMENT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.35))

                    Text(String(format: "%.1f%%", engagement))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(accentColor)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Published View

    @ViewBuilder
    private var publishedView: some View {
        phaseHeader(title: "Published", icon: "paperplane.fill")

        // Published info card
        VStack(alignment: .leading, spacing: 16) {
            if let metadata = atom.metadataValue(as: ContentAtomMetadata.self) {
                publishedInfoRow(metadata)
            }

            // Editable post URL
            VStack(alignment: .leading, spacing: 6) {
                Text("POST URL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.35))

                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(accentColor)

                    TextField("Paste post URL here...", text: $postURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }

            // Track performance button
            Button {
                advanceToAnalyzing()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14))
                    Text("Track Performance")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func publishedInfoRow(_ metadata: ContentAtomMetadata) -> some View {
        HStack(spacing: 16) {
            // Platform badge
            if let platform = metadata.platform {
                HStack(spacing: 6) {
                    Image(systemName: platform.iconName)
                        .font(.system(size: 12))
                    Text(platform.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accentColor.opacity(0.12), in: Capsule())
            }

            // Published date
            if let transition = metadata.lastPhaseTransition {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(transition, style: .relative)
                        .font(.system(size: 11))
                }
                .foregroundColor(.white.opacity(0.4))
            }

            Spacer()
        }
    }

    // MARK: - Analyzing View

    @ViewBuilder
    private var analyzingView: some View {
        phaseHeader(title: "Performance Analytics", icon: "chart.bar")

        // Show real data if available, otherwise manual entry
        if let perf = atom.metadataValue(as: ContentPerformanceMetadata.self) {
            // Real metrics display
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(label: "Impressions", value: formatNumber(perf.impressions), icon: "eye")
                metricCard(label: "Reach", value: formatNumber(perf.reach), icon: "person.2")
                metricCard(label: "Engagement", value: String(format: "%.1f%%", perf.engagementRate * 100), icon: "hand.thumbsup")
                metricCard(label: "Likes", value: formatNumber(perf.likes), icon: "heart")
                metricCard(label: "Comments", value: formatNumber(perf.comments), icon: "bubble.left")
                metricCard(label: "Shares", value: formatNumber(perf.shares), icon: "arrowshape.turn.up.right")
            }

            if perf.saves > 0 || perf.isViral {
                HStack(spacing: 12) {
                    if perf.saves > 0 {
                        metricCard(label: "Saves", value: formatNumber(perf.saves), icon: "bookmark")
                    }
                    if perf.isViral {
                        viralBadge
                    }
                }
            }
        } else {
            // Manual entry fields
            manualEntrySection
        }

        // Archive button
        Button {
            advanceToArchived()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .font(.system(size: 13))
                Text("Archive Content")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var viralBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14))
            Text("VIRAL")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ENTER METRICS")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.35))

            Text("Enter your post metrics from the platform to track performance.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricField(label: "Impressions", text: $impressionsText, icon: "eye")
                metricField(label: "Reach", text: $reachText, icon: "person.2")
                metricField(label: "Likes", text: $likesText, icon: "heart")
                metricField(label: "Comments", text: $commentsText, icon: "bubble.left")
                metricField(label: "Shares", text: $sharesText, icon: "arrowshape.turn.up.right")
                metricField(label: "Saves", text: $savesText, icon: "bookmark")
            }

            Button {
                savePerformanceMetrics()
            } label: {
                HStack(spacing: 8) {
                    if isSavingPerformance {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14))
                    }
                    Text("Save Metrics")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isSavingPerformance)
        }
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func metricField(label: String, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(accentColor.opacity(0.7))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }

            TextField("0", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    // MARK: - Archived View

    @ViewBuilder
    private var archivedView: some View {
        phaseHeader(title: "Archived", icon: "archivebox")

        // Lifecycle summary
        VStack(alignment: .leading, spacing: 16) {
            Text("LIFECYCLE SUMMARY")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.35))

            // Creation date
            archivedRow(
                icon: "calendar.badge.plus",
                label: "Created",
                valueView: AnyView(
                    Text(archivedCreationDate, style: .date)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                )
            )

            // Archived date
            archivedRow(
                icon: "archivebox",
                label: "Archived",
                valueView: AnyView(
                    Text(state.lastModified, style: .date)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                )
            )

            // Word count
            let wc = state.draftContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            archivedRow(
                icon: "text.word.spacing",
                label: "Total Words",
                valueView: AnyView(
                    Text("\(wc)")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                )
            )

            // Total XP earned
            let totalXP = archivedTotalXP
            if totalXP > 0 {
                archivedRow(
                    icon: "star.fill",
                    label: "Total XP Earned",
                    valueView: AnyView(
                        Text("+\(totalXP)")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 1, green: 0.84, blue: 0))
                    )
                )
            }

            // Platform
            if let metadata = atom.metadataValue(as: ContentAtomMetadata.self),
               let platform = metadata.platform {
                archivedRow(
                    icon: platform.iconName,
                    label: "Platform",
                    valueView: AnyView(
                        Text(platform.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(accentColor)
                    )
                )
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))

        // Performance summary (if available)
        if let perf = atom.metadataValue(as: ContentPerformanceMetadata.self) {
            VStack(alignment: .leading, spacing: 16) {
                Text("PERFORMANCE SNAPSHOT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.35))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard(label: "Reach", value: formatNumber(perf.reach), icon: "person.2")
                    metricCard(label: "Engagement", value: String(format: "%.1f%%", perf.engagementRate * 100), icon: "hand.thumbsup")
                    metricCard(label: "Likes", value: formatNumber(perf.likes), icon: "heart")
                }

                if perf.isViral {
                    viralBadge
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        }

        // Repurpose button
        Button {
            repurposeContent()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14))
                Text("Repurpose Content")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(accentColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func archivedRow(icon: String, label: String, valueView: AnyView) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                valueView
            }

            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private var archivedCreationDate: Date {
        if let date = ISO8601DateFormatter().date(from: atom.createdAt) {
            return date
        }
        return Date()
    }

    private var archivedTotalXP: Int {
        // Sum phase completion XP across phases the content went through
        var xp = 0
        for phase in ContentPhase.allCases {
            if phase == .archived { break }
            xp += phase.completionXP
        }
        return xp
    }

    // MARK: - Shared Components

    private func phaseHeader(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(accentColor)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Spacer()
        }
    }

    private var platformPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SocialPlatform.allCases, id: \.self) { platform in
                    platformPill(platform)
                }
            }
        }
    }

    @ViewBuilder
    private func platformPill(_ platform: SocialPlatform) -> some View {
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        let isSelected = metadata?.platform == platform

        Button {
            // Platform selection is informational in this view
        } label: {
            HStack(spacing: 5) {
                Image(systemName: platform.iconName)
                    .font(.system(size: 10))
                Text(platform.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? accentColor.opacity(0.3) : Color.white.opacity(0.06),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func metricCard(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(accentColor.opacity(0.7))

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    /// Notify the parent ViewModel to refresh atom state after a phase change
    private func notifyPhaseChanged() {
        NotificationCenter.default.post(
            name: .contentPhaseChanged,
            object: nil,
            userInfo: ["atomUUID": atom.uuid]
        )
    }

    private func publishNow() {
        if let advance = onAdvancePhase {
            advance(.published)
        } else {
            Task {
                do {
                    let service = ContentPipelineService()
                    try await service.recordPublish(
                        contentUUID: atom.uuid,
                        platform: atom.metadataValue(as: ContentAtomMetadata.self)?.platform ?? .twitter,
                        postId: UUID().uuidString
                    )
                    await MainActor.run { notifyPhaseChanged() }
                } catch {
                    print("PostCreationPhaseView: publish failed: \(error)")
                }
            }
        }
    }

    private func advanceToAnalyzing() {
        if let advance = onAdvancePhase {
            advance(.analyzing)
        } else {
            Task {
                do {
                    let service = ContentPipelineService()
                    try await service.advancePhase(contentUUID: atom.uuid, notes: "Moved to analyzing")
                    await MainActor.run { notifyPhaseChanged() }
                } catch {
                    print("PostCreationPhaseView: advance failed: \(error)")
                }
            }
        }
    }

    private func advanceToArchived() {
        if let advance = onAdvancePhase {
            advance(.archived)
        } else {
            Task {
                do {
                    let service = ContentPipelineService()
                    try await service.advancePhase(contentUUID: atom.uuid, notes: "Archived")
                    await MainActor.run { notifyPhaseChanged() }
                } catch {
                    print("PostCreationPhaseView: archive failed: \(error)")
                }
            }
        }
    }

    private func repurposeContent() {
        Task {
            do {
                let service = ContentPipelineService()
                let newContent = try await service.createContent(
                    title: "Repurposed: \(atom.title ?? "Untitled")",
                    body: state.draftContent
                )
                // Open the new content in focus mode
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openBlockInFocusMode,
                    object: nil,
                    userInfo: ["atomUUID": newContent.uuid]
                )
            } catch {
                print("PostCreationPhaseView: repurpose failed: \(error)")
            }
        }
    }

    private func savePerformanceMetrics() {
        let impressions = Int(impressionsText) ?? 0
        let reach = Int(reachText) ?? 0
        let likes = Int(likesText) ?? 0
        let comments = Int(commentsText) ?? 0
        let shares = Int(sharesText) ?? 0
        let saves = Int(savesText) ?? 0

        guard impressions + reach + likes + comments + shares + saves > 0 else { return }

        isSavingPerformance = true

        Task {
            do {
                let service = ContentPipelineService()
                let platform = atom.metadataValue(as: ContentAtomMetadata.self)?.platform ?? .twitter
                try await service.recordPerformance(
                    contentUUID: atom.uuid,
                    platform: platform,
                    postId: UUID().uuidString,
                    impressions: impressions,
                    reach: reach,
                    likes: likes,
                    comments: comments,
                    shares: shares,
                    saves: saves
                )
                await MainActor.run {
                    isSavingPerformance = false
                    notifyPhaseChanged()
                }
            } catch {
                await MainActor.run {
                    isSavingPerformance = false
                }
                print("PostCreationPhaseView: save performance failed: \(error)")
            }
        }
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
