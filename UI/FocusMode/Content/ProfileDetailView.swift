// CosmoOS/UI/FocusMode/Content/ProfileDetailView.swift
// Post-creation profile detail view with Intelligence, Documents, and Raw Analysis tabs
// February 2026

import SwiftUI

struct ProfileDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let atom: Atom

    @State private var selectedTab = 0
    @State private var intelligenceModel: ClientIntelligenceModel?
    @State private var overrides: [IntelligenceOverride] = []
    @State private var editingMetricId: UUID?
    @State private var editingMetricKey = ""
    @State private var editingMetricValue = ""
    @State private var documents: [ProfileDocument] = []

    private var meta: ClientProfileMetadata? {
        atom.metadataValue(as: ClientProfileMetadata.self)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.border)
            tabBar
            Divider().background(DS.border)
            tabContent
        }
        .frame(width: 620, height: 680)
        .background(DS.surface)
        .cornerRadius(DS.radiusLarge)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge)
                .stroke(DS.border, lineWidth: 1)
        )
        .onAppear { loadProfileData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(DS.accent.opacity(0.15))
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundColor(DS.accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(atom.title ?? "Untitled Profile")
                    .font(DS.cardTitle)
                    .foregroundColor(DS.text)

                HStack(spacing: 8) {
                    if let handle = meta?.handle, !handle.isEmpty {
                        Text(handle)
                            .font(DS.cardMeta)
                            .foregroundColor(DS.textSecondary)
                    }

                    if let platform = meta?.primaryPlatform {
                        platformBadge(platform)
                    } else if let platforms = meta?.platforms, let first = platforms.first {
                        platformBadge(first)
                    }

                }
            }

            Spacer()

            // Migration banner
            if hasLegacyFields {
                migrationBanner
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(DS.buttonText)
                    .foregroundColor(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func platformBadge(_ platform: SocialPlatform) -> some View {
        HStack(spacing: 3) {
            Image(systemName: platform.iconName)
                .font(.system(size: 8))
            Text(platform.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(DS.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(DS.accent.opacity(0.12))
        )
    }

    private var hasLegacyFields: Bool {
        guard let meta = meta else { return false }
        let hasOldTranscripts = meta.topPerformingTranscripts != nil && !(meta.topPerformingTranscripts?.isEmpty ?? true)
        let hasLegacyMap = meta.legacyFields != nil && !(meta.legacyFields?.isEmpty ?? true)
        return hasOldTranscripts || hasLegacyMap
    }

    private var migrationBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundColor(DS.orange)
            Text("Legacy data — re-save to migrate")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.orange.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(DS.orange.opacity(0.08))
        )
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Intelligence", index: 0)
            tabButton(title: "Documents", index: 1)
            tabButton(title: "Raw Analysis", index: 2)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func tabButton(title: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index } }) {
            tabButtonLabel(title: title, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabButtonLabel(title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundColor(isSelected ? DS.text : DS.textMuted)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(DS.accent)
                        .frame(height: 2)
                }
            }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            switch selectedTab {
            case 0: intelligenceTab
            case 1: documentsTab
            case 2: rawAnalysisTab
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab 1: Intelligence

    private var intelligenceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let model = Binding($intelligenceModel) {
                IntelligenceModelView(
                    model: model,
                    overrides: $overrides,
                    editingMetricId: $editingMetricId,
                    editingMetricKey: $editingMetricKey,
                    editingMetricValue: $editingMetricValue,
                    showUpdateButton: true,
                    onUpdateRequested: {
                        Task { await regenerateModel() }
                    }
                )
            } else {
                emptyIntelligenceState
            }
        }
        .padding(20)
    }

    private var emptyIntelligenceState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundColor(DS.borderActive)

            Text("No intelligence model generated")
                .font(DS.sectionDesc)
                .foregroundColor(DS.textMuted)

            Text("Edit this profile and upload documents to generate a model.")
                .font(DS.timestamp)
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Tab 2: Documents

    private var documentsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if documents.isEmpty {
                emptyDocumentsState
            } else {
                ForEach(ProfileDocumentCategory.allCases, id: \.self) { category in
                    let filtered = documents.filter { $0.category == category }
                    if !filtered.isEmpty {
                        documentCategorySection(category: category, docs: filtered)
                    }
                }
            }
        }
        .padding(20)
    }

    private var emptyDocumentsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 32))
                .foregroundColor(DS.borderActive)

            Text("No documents uploaded")
                .font(DS.sectionDesc)
                .foregroundColor(DS.textMuted)

            Text("Edit this profile to add brand story, top performers, and voice guides.")
                .font(DS.timestamp)
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func documentCategorySection(category: ProfileDocumentCategory, docs: [ProfileDocument]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.system(size: 10))
                    .foregroundColor(DS.accent.opacity(0.7))

                Text(category.displayName.uppercased())
                    .font(DS.sectionLabel)
                    .foregroundColor(DS.textMuted)
                    .tracking(1.0)

                Text("\(docs.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DS.border))
            }

            ForEach(docs) { doc in
                readOnlyDocumentCard(doc)
            }
        }
    }

    @ViewBuilder
    private func readOnlyDocumentCard(_ doc: ProfileDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                    .font(DS.buttonText)
                    .foregroundColor(DS.text)

                Spacer()

                if doc.category.hasMetrics {
                    metricsChips(doc)
                }

                Text("\(doc.content.count) chars")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }

            Text(String(doc.content.prefix(200)) + (doc.content.count > 200 ? "..." : ""))
                .font(DS.timestamp)
                .foregroundColor(DS.textSecondary)
                .lineLimit(4)
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func metricsChips(_ doc: ProfileDocument) -> some View {
        HStack(spacing: 4) {
            if let likes = doc.likes, likes > 0 {
                metricChip(icon: "heart.fill", value: "\(likes)")
            }
            if let shares = doc.shares, shares > 0 {
                metricChip(icon: "arrow.turn.up.right", value: "\(shares)")
            }
            if let saves = doc.saves, saves > 0 {
                metricChip(icon: "bookmark.fill", value: "\(saves)")
            }
            if let leads = doc.leads, leads > 0 {
                metricChip(icon: "person.badge.plus", value: "\(leads)")
            }
        }
    }

    @ViewBuilder
    private func metricChip(icon: String, value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text(value)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundColor(DS.textMuted)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(DS.borderSubtle, in: Capsule())
    }

    // MARK: - Tab 3: Raw Analysis

    private var rawAnalysisTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RAW METADATA")
                .font(DS.sectionLabel)
                .foregroundColor(DS.textMuted)
                .tracking(1.0)

            let jsonText = atom.metadata ?? "{}"

            ScrollView(.horizontal, showsIndicators: true) {
                Text(prettyPrintJSON(jsonText))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DS.textSecondary)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func prettyPrintJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return result
    }

    private func loadProfileData() {
        guard let meta = meta else { return }

        // Load intelligence model
        intelligenceModel = meta.intelligenceModel
        overrides = meta.intelligenceModel?.userOverrides ?? []

        // Load documents from new document library if available
        if let docs = meta.documents, !docs.isEmpty {
            documents = docs
        } else {
            // Fallback: reconstruct from legacy fields
            if let story = meta.brandStory, !story.isEmpty {
                documents.append(ProfileDocument(category: .story, title: "Brand Story", content: story))
            }
            if let voice = meta.voiceNotes, !voice.isEmpty {
                documents.append(ProfileDocument(category: .voiceGuide, title: "Voice Notes", content: voice))
            }
            if let posts = meta.topPerformingPosts {
                for post in posts where !post.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let category = inferDocCategory(from: post.transcript)
                    documents.append(ProfileDocument(
                        category: category,
                        title: "\(category == .reel ? "Reel" : "Thread") (\(post.platform.isEmpty ? "unknown" : post.platform))",
                        content: post.transcript,
                        platform: post.platform,
                        likes: post.likes,
                        shares: post.shares,
                        leads: post.leads
                    ))
                }
            }
        }
    }

    private func inferDocCategory(from content: String) -> ProfileDocumentCategory {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceCount = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        if trimmed.count < 500 || sentenceCount < 5 { return .reel }
        return .thread
    }

    private func regenerateModel() async {
        do {
            let newModel = try await ClientIntelligenceEngine.shared.generateModel(profile: atom)
            await MainActor.run {
                intelligenceModel = newModel
                overrides = newModel.userOverrides
            }
        } catch {
            print("[ProfileDetailView] Failed to regenerate model: \(error)")
        }
    }
}

