// CosmoOS/Canvas/IdeaBoardBlockView.swift
// Live-updating client idea board canvas block
// Renders the IDENTICAL UI as the CMD+K Ideas tab column — same IdeaBoardCard, same layout
// Data fetched via GRDB observation, rebuilt into IdeaClientSection for the shared components

import SwiftUI
import GRDB

struct IdeaBoardBlockView: View {

    let block: CanvasBlock

    @State private var section: IdeaClientSection?
    @State private var isLoading = true
    @State private var observation: AnyDatabaseCancellable?
    @State private var hasAppeared = false

    private var clientUUID: String? {
        let uuid = block.metadata["clientUUID"]
        return (uuid?.isEmpty == true) ? nil : uuid
    }
    private var clientName: String { block.metadata["clientName"] ?? block.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            boardHeader

            Divider()
                .background(sectionColor.opacity(0.2))

            // Cards — identical to IdeasTab boardColumn
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if let section {
                        ForEach(
                            Array(section.items.enumerated()),
                            id: \.element.id
                        ) { index, item in
                            IdeaBoardCard(
                                item: item,
                                columnColor: section.color,
                                viewModel: nil,
                                hasAppeared: hasAppeared,
                                appearDelay: Double(index) * 0.04
                            )
                            .draggable(item.atomUUID)
                        }

                        if section.items.isEmpty {
                            emptyPlaceholder
                        }
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 280, height: 400)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .shadow(color: .black.opacity(0.02), radius: 2, y: 1)
        .task {
            await loadIdeas()
            startObservation()
            withAnimation(ProMotionSprings.snappy) {
                hasAppeared = true
            }
        }
        .onDisappear {
            observation?.cancel()
        }
    }

    // MARK: - Header (matches IdeasTab columnHeader)

    private var boardHeader: some View {
        HStack(spacing: 8) {
            Text(clientName.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(sectionColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(sectionColor.opacity(0.10))
                )

            Text("\(section?.items.count ?? 0)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(sectionColor.opacity(0.8))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Empty (matches IdeasTab emptyColumnPlaceholder)

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(sectionColor.opacity(0.25))

            Text("No ideas yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Color

    private var sectionColor: Color {
        if let uuid = clientUUID {
            // Use the same client color assignment as IdeasTab
            let hash = abs(uuid.hashValue)
            let colors: [Color] = [
                DS.entityIdea, DS.entityContent, DS.entityConnection,
                DS.entityResearch, DS.entitySwipe, DS.entityTask
            ]
            return colors[hash % colors.count]
        }
        return DS.entityIdea
    }

    // MARK: - Data Loading (same query as IdeasTab sections builder)

    private func loadIdeas() async {
        do {
            let allIdeas = try await AtomRepository.shared.fetchAll(type: .idea)

            let clientItems: [IdeaGalleryItem] = allIdeas.compactMap { atom -> IdeaGalleryItem? in
                // Filter to this client
                if let uuid = clientUUID {
                    let meta = atom.ideaMetadata
                    let links = atom.linksList
                    let matchesClient = meta?.clientUUID == uuid ||
                        links.contains { $0.uuid == uuid }
                    guard matchesClient else { return nil }
                }

                return atom.toIdeaGalleryItem(clientName: clientName)
            }
            .sorted { $0.updatedAt > $1.updatedAt }

            section = IdeaClientSection(
                id: clientUUID ?? "unassigned",
                clientName: clientName,
                clientUUID: clientUUID,
                color: sectionColor,
                items: clientItems
            )

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
}
