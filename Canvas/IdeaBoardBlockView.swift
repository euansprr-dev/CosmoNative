// CosmoOS/Canvas/IdeaBoardBlockView.swift
// Live-updating client idea board canvas block
// Shows a client's ideas filtered by status, auto-updates via GRDB observation
// Dragged from Command-K onto the canvas — Command-K is the "component library"

import SwiftUI
import GRDB

struct IdeaBoardBlockView: View {

    let block: CanvasBlock

    @State private var ideas: [IdeaBoardItem] = []
    @State private var isLoading = true
    @State private var observation: AnyDatabaseCancellable?

    private var clientUUID: String? { block.metadata["clientUUID"] }
    private var clientName: String { block.metadata["clientName"] ?? block.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            boardHeader
            Divider().padding(.horizontal, 12)
            ideaList
            boardFooter
        }
        .frame(width: 280, height: 400)
        .background(DS.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .task {
            await loadIdeas()
            startObservation()
        }
        .onDisappear {
            observation?.cancel()
        }
    }

    // MARK: - Header

    private var boardHeader: some View {
        HStack(spacing: 8) {
            // Client avatar circle
            Circle()
                .fill(DS.entityIdea)
                .frame(width: 22, height: 22)
                .overlay(
                    Text(clientName.prefix(1).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(clientName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Text("IDEA BOARD")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.textMuted)
                    .tracking(0.6)
            }

            Spacer()

            // Live indicator
            HStack(spacing: 3) {
                Circle()
                    .fill(DS.green)
                    .frame(width: 4, height: 4)

                Text("LIVE")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DS.green)
                    .tracking(0.4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Idea List

    private var ideaList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else if ideas.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(ideas) { idea in
                        ideaRow(idea)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func ideaRow(_ idea: IdeaBoardItem) -> some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(idea.statusColor)
                .frame(width: 6, height: 6)

            Text(idea.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let format = idea.format {
                Text(format)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .tracking(0.3)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DS.surfaceHover))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(DS.textMuted.opacity(0.4))

            Text("No ideas yet")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    // MARK: - Footer

    private var boardFooter: some View {
        HStack {
            Text("\(ideas.count) idea\(ideas.count == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .monospacedDigit()

            Spacer()

            // Status breakdown
            let sparkCount = ideas.filter { $0.status == "spark" }.count
            let devCount = ideas.filter { $0.status == "developing" }.count
            if sparkCount > 0 || devCount > 0 {
                HStack(spacing: 4) {
                    if sparkCount > 0 {
                        statusPill(count: sparkCount, color: .orange, label: "spark")
                    }
                    if devCount > 0 {
                        statusPill(count: devCount, color: DS.accent, label: "dev")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DS.surfaceHover.opacity(0.5))
    }

    private func statusPill(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DS.textMuted)
        }
        .accessibilityLabel("\(count) \(label)")
    }

    // MARK: - Data

    private func loadIdeas() async {
        do {
            var atoms = try await AtomRepository.shared.fetchAll(type: .idea)

            // Filter by client
            if let uuid = clientUUID {
                atoms = atoms.filter { atom in
                    let links = atom.linksList
                    return links.contains { $0.uuid == uuid } ||
                           atom.ideaMetadata?.clientUUID == uuid
                }
            }

            // Sort by most recent
            atoms.sort { $0.updatedAt > $1.updatedAt }

            ideas = atoms.prefix(30).map { atom in
                let meta = atom.ideaMetadata
                return IdeaBoardItem(
                    id: atom.uuid,
                    title: atom.title ?? "(untitled)",
                    status: meta?.ideaStatus?.rawValue ?? "spark",
                    format: meta?.contentFormat?.rawValue,
                    statusColor: statusColor(for: meta?.ideaStatus)
                )
            }

            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func startObservation() {
        guard let db = CosmoDatabase.shared.dbQueue else { return }

        let obs = ValueObservation.tracking { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM atoms WHERE type = 'idea' AND is_deleted = 0") ?? 0
        }

        observation = obs.start(in: db, onError: { _ in }) { [self] _ in
            Task { @MainActor in
                await loadIdeas()
            }
        }
    }

    private func statusColor(for status: IdeaStatus?) -> Color {
        switch status {
        case .spark: return .orange
        case .developing: return DS.accent
        case .ready: return DS.green
        case .inProduction: return DS.info
        case .published: return DS.green
        case .archived: return DS.textMuted
        case nil: return DS.textMuted
        }
    }
}

// MARK: - Data Model

struct IdeaBoardItem: Identifiable {
    let id: String
    let title: String
    let status: String
    let format: String?
    let statusColor: Color
}
