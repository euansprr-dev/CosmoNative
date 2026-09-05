// CosmoOS/Canvas/DeepDivePortalBlockView.swift
// Deep Dive portal block: a doorway to a focused topic mastery environment.
// Lives inside Thinkspaces alongside notes/connections/sources, but reads as a portal
// (subtle gradient, maturity dot, two clear actions). Plan §18.

import SwiftUI
import GRDB

struct DeepDivePortalBlockView: View {
    let block: CanvasBlock

    @State private var atom: Atom?
    @State private var questionCount: Int = 0
    @State private var sourceCount: Int = 0
    @State private var lexiconCount: Int = 0
    @State private var connectionCount: Int = 0
    @State private var sessionCount: Int = 0
    @State private var currentQuestionTitle: String?
    @State private var isLoading = true
    @State private var isHovered = false

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: CosmoMentionColors.color(for: .deepDive),
            icon: "circle.hexagongrid.circle.fill",
            title: atom?.title ?? block.title,
            onFocusMode: openOverview
        ) {
            content
                .onHover { isHovered = $0 }
        }
        .onAppear { loadAtom() }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: DS.space12) {
                typeBadge
                titleSection
                if let q = currentQuestionTitle, !q.isEmpty {
                    currentQuestionLine(q)
                }
                Rectangle()
                    .fill(DS.borderSubtle)
                    .frame(height: 1)
                    .padding(.vertical, DS.space2)
                metadataRow
                Spacer(minLength: 0)
                actionRow
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space12)
        }
    }

    // MARK: - Sections

    private var typeBadge: some View {
        HStack {
            Text("DEEP DIVE")
                .font(CosmoTypography.labelSmall)
                .tracking(2)
                .foregroundStyle(DS.accent.opacity(0.78))
            Spacer()
            maturityChip
        }
    }

    private var maturityChip: some View {
        let maturity = atom?.deepDiveMetadata?.maturity ?? .spark
        return HStack(spacing: DS.space6) {
            Circle()
                .fill(maturityColor(maturity))
                .frame(width: 6, height: 6)
            Text(maturity.displayName)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
        }
    }

    private var titleSection: some View {
        Text(atom?.title ?? block.title)
            .font(.system(size: 22, weight: .semibold, design: .serif))
            .foregroundStyle(CosmoColors.textPrimary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currentQuestionLine(_ q: String) -> some View {
        Text(q)
            .font(CosmoTypography.body.italic())
            .foregroundStyle(CosmoColors.textSecondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataRow: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text(metadataLine1)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary.opacity(0.85))
            if let updated = updatedLabel {
                Text(updated)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
        }
    }

    private var metadataLine1: String {
        var parts: [String] = []
        if questionCount > 0 { parts.append("\(questionCount) question\(questionCount == 1 ? "" : "s")") }
        if sourceCount > 0 { parts.append("\(sourceCount) source\(sourceCount == 1 ? "" : "s")") }
        if lexiconCount > 0 { parts.append("\(lexiconCount) lexicon") }
        if connectionCount > 0 { parts.append("\(connectionCount) concept\(connectionCount == 1 ? "" : "s")") }
        if sessionCount > 0 { parts.append("\(sessionCount) session\(sessionCount == 1 ? "" : "s")") }
        return parts.isEmpty ? "Just sparked — no captures yet" : parts.joined(separator: " · ")
    }

    private var updatedLabel: String? {
        let dateString = atom?.deepDiveMetadata?.lastInquiryAt ?? atom?.updatedAt
        guard let dateString,
              let date = ISO8601.date(from: dateString) else { return nil }
        return "Updated \(CosmoDateFormatters.relative.localizedString(for: date, relativeTo: Date()))"
    }

    private var actionRow: some View {
        HStack(spacing: DS.space8) {
            Button(action: openOverview) {
                HStack(spacing: DS.space6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Open")
                        .font(CosmoTypography.label)
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(DS.accent.opacity(0.92), in: Capsule())
                .foregroundStyle(DS.textOnAccent)
            }
            .buttonStyle(.plain)

            Button(action: startInquiry) {
                HStack(spacing: DS.space6) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Start Inquiry")
                        .font(CosmoTypography.label)
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .overlay(Capsule().stroke(DS.accent.opacity(0.55), lineWidth: 1))
                .foregroundStyle(DS.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading

    private func loadAtom() {
        Task {
            do {
                let loaded: Atom?
                if !block.entityUuid.isEmpty {
                    loaded = try await AtomRepository.shared.fetch(uuid: block.entityUuid)
                } else if block.entityId > 0 {
                    loaded = try await AtomRepository.shared.fetch(id: block.entityId)
                } else {
                    loaded = nil
                }
                guard let dd = loaded, dd.type == .deepDive else {
                    await MainActor.run { isLoading = false }
                    return
                }
                await MainActor.run {
                    atom = dd
                    isLoading = false
                }
                await loadCounts(for: dd)
                await loadCurrentQuestionTitle(for: dd)
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func loadCounts(for dd: Atom) async {
        async let questions = (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: dd.uuid)) ?? []
        async let lexicon = (try? await InquiryRepository.shared.fetchLexicon(forDeepDive: dd.uuid)) ?? []
        async let sessions = (try? await InquiryRepository.shared.fetchSessions(forDeepDive: dd.uuid)) ?? []
        async let sources = (try? await InquiryRepository.shared.fetchSources(forDeepDive: dd)) ?? []
        async let connections = (try? await InquiryRepository.shared.fetchConnections(forDeepDive: dd)) ?? []
        let (qs, lx, ss, src, cx) = await (questions, lexicon, sessions, sources, connections)
        await MainActor.run {
            questionCount = qs.filter { ($0.questionMetadata?.status ?? .open) != .archived }.count
            lexiconCount = lx.count
            sessionCount = ss.count
            sourceCount = src.count
            connectionCount = cx.count
        }
    }

    private func loadCurrentQuestionTitle(for dd: Atom) async {
        let questions = (try? await InquiryRepository.shared.fetchQuestions(forDeepDive: dd.uuid)) ?? []
        let active = questions.first { ($0.questionMetadata?.status ?? .open) == .researching }
            ?? questions.first { ($0.questionMetadata?.status ?? .open) == .open }
            ?? questions.first
        await MainActor.run {
            currentQuestionTitle = active?.title
        }
    }

    private func maturityColor(_ m: DeepDiveMaturity) -> Color {
        switch m {
        case .spark: return CosmoColors.textTertiary
        case .exploring: return DS.accent.opacity(0.55)
        case .developing: return DS.accent
        case .mature: return DS.accent.opacity(0.95)
        case .evolving: return CosmoMentionColors.color(for: .deepDive)
        }
    }

    // MARK: - Actions

    private func openOverview() {
        guard let atom else { return }
        // ONE open path. `openDeepDive` reaches FocusNavigationCoordinator,
        // where the space routing policy decides between the dossier inside
        // its space and a focus overlay; a second `.enterFocusMode` post used
        // to bypass that decision.
        NotificationCenter.default.post(
            name: CosmoNotification.Inquiry.openDeepDive,
            object: nil,
            userInfo: ["uuid": atom.uuid]
        )
    }

    private func startInquiry() {
        guard let atom else { return }
        NotificationCenter.default.post(
            name: CosmoNotification.Inquiry.startInquiry,
            object: nil,
            userInfo: [
                "anchorUUID": atom.uuid,
                "anchorType": AtomType.deepDive.rawValue
            ]
        )
    }
}
