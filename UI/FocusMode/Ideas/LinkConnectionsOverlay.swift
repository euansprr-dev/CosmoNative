// CosmoOS/UI/FocusMode/Ideas/LinkConnectionsOverlay.swift
// Full-screen overlay for linking connections to an idea
// February 2026

import SwiftUI

struct LinkConnectionsOverlay: View {
    @ObservedObject var viewModel: IdeaFocusModeViewModel
    @Binding var isPresented: Bool

    @State private var searchText: String = ""
    @State private var allConnections: [Atom] = []
    @State private var selectedUUIDs: Set<String> = []
    @State private var isLoading: Bool = true

    private let overlayWidth: CGFloat = 700
    private let overlayHeight: CGFloat = 600
    private let accentColor = DS.accent

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            // Container
            VStack(spacing: 0) {
                overlayHeader
                Divider().background(DS.border)
                searchField
                Divider().background(DS.border)
                connectionList
                Divider().background(DS.border)
                overlayFooter
            }
            .frame(width: overlayWidth, height: overlayHeight)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(DS.surface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(DS.border)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [DS.border, DS.borderSubtle],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        }
        .onAppear { Task { await loadAllConnections() } }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Header

    private var overlayHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 14))
                .foregroundStyle(accentColor)

            Text("Link Connections")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.text)

            Spacer()

            if !selectedUUIDs.isEmpty {
                Text("\(selectedUUIDs.count) selected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .padding(8)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(DS.textMuted)

            TextField("Search connections by name, topic...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.text)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DS.borderSubtle)
    }

    // MARK: - Connection List

    private var connectionList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(accentColor)
                    Text("Loading connections...")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else if filteredConnections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 28))
                        .foregroundStyle(DS.textMuted)
                    Text(searchText.isEmpty ? "No connections found" : "No connections match '\(searchText)'")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(filteredConnections, id: \.uuid) { connection in
                        connectionRow(connection)
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredConnections: [Atom] {
        let linkedIds = Set(viewModel.idea.ideaMetadata?.linkedConnectionIds ?? [])
        let clientUUID = viewModel.idea.ideaMetadata?.clientUUID
        let search = searchText.lowercased().trimmingCharacters(in: .whitespaces)

        return allConnections.filter { conn in
            if search.isEmpty { return true }
            let title = (conn.title ?? "").lowercased()
            let body = (conn.body ?? "").lowercased()
            let goal = (connectionGoalText(conn) ?? "").lowercased()
            return title.contains(search) || body.contains(search) || goal.contains(search)
        }.sorted { a, b in
            // Already-linked first, then client connections, then by recency
            let aLinked = linkedIds.contains(a.uuid)
            let bLinked = linkedIds.contains(b.uuid)
            if aLinked != bLinked { return aLinked }

            if let cid = clientUUID {
                let aClient = hasClientLink(a, clientUUID: cid)
                let bClient = hasClientLink(b, clientUUID: cid)
                if aClient != bClient { return aClient }
            }

            return (a.updatedAt ?? "") > (b.updatedAt ?? "")
        }
    }

    @ViewBuilder
    private func connectionRow(_ connection: Atom) -> some View {
        let linkedIds = Set(viewModel.idea.ideaMetadata?.linkedConnectionIds ?? [])
        let isAlreadyLinked = linkedIds.contains(connection.uuid)
        let isSelected = selectedUUIDs.contains(connection.uuid)
        let maturity = resolveMaturity(connection)
        let filledCount = connectionFilledSectionCount(connection)

        Button {
            if isAlreadyLinked { return }
            if isSelected {
                selectedUUIDs.remove(connection.uuid)
            } else {
                selectedUUIDs.insert(connection.uuid)
            }
        } label: {
            HStack(spacing: 12) {
                // Icon
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 16))
                            .foregroundStyle(accentColor.opacity(0.7))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    // Name
                    Text(connection.title ?? "Untitled Connection")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.text)
                        .lineLimit(1)

                    // Badges
                    HStack(spacing: 6) {
                        maturityBadge(maturity)

                        Text("\(filledCount)/8 sections")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.textMuted)

                        if let cid = viewModel.idea.ideaMetadata?.clientUUID,
                           hasClientLink(connection, clientUUID: cid) {
                            Text("Client")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(DS.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    // Goal preview from structured data
                    if let goalText = connectionGoalText(connection), !goalText.isEmpty {
                        Text(String(goalText.prefix(80)))
                            .font(.system(size: 10))
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Status indicator
                if isAlreadyLinked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.green)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(accentColor)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.textMuted)
                }
            }
            .padding(10)
            .background(
                (isAlreadyLinked ? DS.green.opacity(0.06) :
                    isSelected ? accentColor.opacity(0.08) : DS.borderSubtle),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isAlreadyLinked ? DS.green.opacity(0.2) :
                            isSelected ? accentColor.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyLinked)
        .opacity(isAlreadyLinked ? 0.7 : 1)
    }

    @ViewBuilder
    private func maturityBadge(_ level: ConnectionMaturityLevel) -> some View {
        let color = maturityColor(level)
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(level.displayName)
                .font(DS.smallCaps)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Footer

    private var overlayFooter: some View {
        HStack(spacing: 12) {
            Text("\(allConnections.count) connections in library")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)

            Spacer()

            Button {
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DS.border, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    for uuid in selectedUUIDs {
                        await viewModel.linkConnection(uuid)
                    }
                    selectedUUIDs.removeAll()
                    isPresented = false
                }
            } label: {
                Text("Link Selected (\(selectedUUIDs.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(selectedUUIDs.isEmpty)
            .opacity(selectedUUIDs.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Data

    private func loadAllConnections() async {
        isLoading = true
        defer { isLoading = false }
        do {
            allConnections = try await AtomRepository.shared.fetchAll(type: .connection)
        } catch {
            print("LinkConnectionsOverlay: failed to load connections: \(error)")
        }
    }

    private func hasClientLink(_ conn: Atom, clientUUID: String) -> Bool {
        guard let meta = conn.metadata,
              let data = meta.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = json["linkedProfileUUIDs"] as? [String] else {
            return false
        }
        return profiles.contains(clientUUID)
    }

    private func resolveMaturity(_ conn: Atom) -> ConnectionMaturityLevel {
        if let cached = conn.connectionMaturityLevel,
           let level = ConnectionMaturityLevel(rawValue: cached) {
            return level
        }
        let count = connectionFilledSectionCount(conn)
        if count >= 6 { return .proven }
        if count >= 4 { return .mature }
        if count >= 2 { return .developing }
        return .seed
    }

    private func connectionFilledSectionCount(_ conn: Atom) -> Int {
        guard let structured = conn.structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return 0
        }
        return data.sections.filter { !$0.items.isEmpty }.count
    }

    private func connectionGoalText(_ conn: Atom) -> String? {
        guard let structured = conn.structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return nil
        }
        let goalSection = data.sections.first { $0.type == .goal }
        return goalSection?.items.first?.content
    }

    private func maturityColor(_ level: ConnectionMaturityLevel) -> Color {
        switch level {
        case .seed: return Color(hex: "9CA3AF")
        case .developing: return Color(hex: "FBBF24")
        case .mature: return Color(hex: "22C55E")
        case .proven: return Color(hex: "6366F1")
        }
    }
}

// MARK: - Preview

#Preview("Link Connections Overlay") {
    @Previewable @State var isPresented = true
    let previewAtom = Atom.new(
        type: .idea,
        title: "Sample Idea for Preview",
        body: "This is a sample idea to demonstrate the link connections overlay."
    )

    LinkConnectionsOverlay(
        viewModel: IdeaFocusModeViewModel(atom: previewAtom),
        isPresented: $isPresented
    )
    .frame(width: 800, height: 700)
}
