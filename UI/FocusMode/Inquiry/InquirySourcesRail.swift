// CosmoOS/UI/FocusMode/Inquiry/InquirySourcesRail.swift
// Right rail of the Stele shell. Clean source list + Deep Scout button.

import SwiftUI

@MainActor
struct InquirySourcesRail: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            railHeader
            Divider().background(DS.borderSubtle)
            sourceList
            Divider().background(DS.borderSubtle)
            deepScoutFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var railHeader: some View {
        HStack(spacing: 6) {
            Text("SOURCES")
                .dsSmallCapsLabel()
            Spacer()
            Text("\(visibleSources.count)")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    @ViewBuilder
    private var sourceList: some View {
        if visibleSources.isEmpty && candidates.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space8) {
                    ForEach(visibleSources, id: \.sourceUUID) { ref in
                        InquirySourceRow(viewModel: viewModel, ref: ref)
                    }
                    if !candidates.isEmpty {
                        candidatesSection
                    }
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Spacer(minLength: DS.space40)
            Image(systemName: "books.vertical")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(CosmoColors.textTertiary)
                .accessibilityHidden(true)
            Text("No sources yet. Paste a URL in the dock or run Deep Scout below.")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(CosmoColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.space20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("CANDIDATES")
                .dsSmallCapsLabel()
                .padding(.top, DS.space8)
            ForEach(candidates.prefix(8), id: \.id) { candidate in
                InquiryCandidateRow(viewModel: viewModel, candidate: candidate)
            }
        }
    }

    private var deepScoutFooter: some View {
        VStack(spacing: 0) {
            if let line = viewModel.sourceActivityLine {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                    Text(line)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await viewModel.refreshSourceRecommendations(query: nil, mode: .deepScout) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Deep Scout")
                        .font(CosmoTypography.label)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(DS.accentSoft, in: Capsule())
                .overlay(Capsule().stroke(DS.accent.opacity(0.25), lineWidth: 1))
                .foregroundStyle(DS.accent)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshingSources)
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space12)
            .accessibilityLabel("Run Deep Scout source search")
        }
    }

    // MARK: - Data

    private var visibleSources: [InquirySourceRef] {
        viewModel.structured.sourceRefs
            .filter { $0.status != .archived && $0.status != .deleted }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private var candidates: [InquirySourceCandidate] {
        viewModel.activeSourceCandidates.filter { $0.importStatus == .candidate }
    }
}

// MARK: - Source row

@MainActor
struct InquirySourceRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let ref: InquirySourceRef

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            viewModel.openReader(forSourceRef: ref)
        } label: {
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.accent.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ref.title)
                        .font(CosmoTypography.bodySmall)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(metaLine)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space10)
            .background(isHovered ? DS.surfaceHover : DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.sepiaSubtle, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Open source: \(ref.title)")
    }

    private var iconName: String {
        if let url = ref.url, !url.isEmpty {
            return "globe"
        }
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
        if ref.extractCount > 0 { parts.append("\(ref.extractCount) extracts") } else if ref.noteCount > 0 { parts.append("\(ref.noteCount) notes") }
        if parts.isEmpty { parts.append(ref.status.displayName) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Candidate row

@MainActor
struct InquiryCandidateRow: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let candidate: InquirySourceCandidate

    var body: some View {
        Button {
            Task { await viewModel.importSourceCandidate(candidate) }
        } label: {
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: candidate.sourceKind.iconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.title)
                        .font(CosmoTypography.bodySmall)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(candidate.provider.displayName) · \(candidate.evidenceRole.displayName)")
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(CosmoColors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(DS.sepiaSubtle, lineWidth: 0.5)
                    .opacity(0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import candidate: \(candidate.title)")
    }
}
