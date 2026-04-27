// CosmoOS/UI/Inbox/CaptureLanesView.swift
// Custom Capture Lanes management and capture review surface.

import AppKit
import SwiftUI

@Observable
@MainActor
final class CaptureLanesViewModel {
    var destinations: [CaptureDestination] = []
    var selectedDestinationId: String?
    var selectedItems: [CapturedItem] = []
    var attachmentsByItemId: [String: [MediaAttachment]] = [:]
    var newLaneName = ""
    var isCreatingLane = false

    private let destinationRepo = CaptureDestinationRepository.shared
    private let capturedRepo = CapturedItemRepository.shared
    private let mediaRepo = MediaAttachmentRepository.shared

    var selectedDestination: CaptureDestination? {
        destinations.first { $0.uuid == selectedDestinationId }
    }

    func refresh() async {
        destinations = (try? await destinationRepo.fetchActive()) ?? destinationRepo.destinations
        if selectedDestinationId == nil {
            selectedDestinationId = destinations.first?.uuid
        }
        await loadItems()
    }

    func select(_ destination: CaptureDestination?) {
        selectedDestinationId = destination?.uuid
        Task { await loadItems() }
    }

    func createLane() async {
        let name = newLaneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isCreatingLane = true
        defer { isCreatingLane = false }
        do {
            let lane = try await destinationRepo.createLane(named: name)
            newLaneName = ""
            destinations = try await destinationRepo.fetchActive()
            selectedDestinationId = lane.uuid
            await loadItems()
        } catch {
            print("CaptureLanesViewModel.createLane failed: \(error)")
        }
    }

    private func loadItems() async {
        selectedItems = (try? await capturedRepo.fetch(destinationId: selectedDestinationId)) ?? []
        var map: [String: [MediaAttachment]] = [:]
        for item in selectedItems {
            map[item.uuid] = (try? await mediaRepo.fetch(capturedItemId: item.uuid)) ?? []
        }
        attachmentsByItemId = map
    }
}

struct CaptureLanesView: View {
    @State private var viewModel = CaptureLanesViewModel()

    var body: some View {
        HStack(spacing: 0) {
            laneSidebar
            Divider().foregroundStyle(DS.borderSubtle)
            laneDetail
        }
        .background(DS.bg)
        .task { await viewModel.refresh() }
    }

    private var laneSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            newLaneComposer
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.destinations) { destination in
                        CaptureLaneSidebarRow(
                            destination: destination,
                            isSelected: viewModel.selectedDestinationId == destination.uuid,
                            onSelect: { viewModel.select(destination) }
                        )
                    }
                }
                .padding(.horizontal, DS.space12)
                .padding(.vertical, DS.space8)
            }
            commandRegistry
        }
        .frame(width: 280)
        .background(DS.surface)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Capture Lanes")
                .font(DS.title2)
                .foregroundStyle(DS.text)
            Text("Telegram commands with durable homes")
                .font(DS.subheadline)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, DS.space16)
        .padding(.top, DS.space16)
        .padding(.bottom, DS.space12)
    }

    private var newLaneComposer: some View {
        HStack(spacing: 8) {
            TextField("New lane", text: $viewModel.newLaneName)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(DS.surfaceElevated, in: .rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                )

            Button {
                Task { await viewModel.createLane() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.textOnAccent)
            .background(DS.accent, in: .rect(cornerRadius: 8))
            .disabled(viewModel.isCreatingLane)
            .accessibilityLabel("Create capture lane")
        }
        .padding(.horizontal, DS.space16)
        .padding(.bottom, DS.space8)
    }

    private var commandRegistry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Telegram Commands")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .textCase(.uppercase)
            ForEach(viewModel.destinations.prefix(5)) { destination in
                HStack(spacing: 6) {
                    Text("\(destination.aliases.first ?? destination.name.lowercased()):")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.accent)
                    Text("-> \(destination.name)")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(DS.space16)
        .overlay(alignment: .top) {
            Divider().foregroundStyle(DS.borderSubtle)
        }
    }

    private var laneDetail: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider().foregroundStyle(DS.borderSubtle)
            if viewModel.selectedItems.isEmpty {
                emptyState
            } else {
                captureList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg)
    }

    @ViewBuilder
    private var detailHeader: some View {
        if let destination = viewModel.selectedDestination {
            HStack(spacing: 12) {
                Image(systemName: destination.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 34, height: 34)
                    .background(DS.accentSoft, in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.name)
                        .font(DS.title1)
                        .foregroundStyle(DS.text)
                    Text("\(destination.type.displayName) lane · \(destination.itemCount) captures")
                        .font(DS.callout)
                        .foregroundStyle(DS.textMuted)
                }

                Spacer()

                Text((destination.aliases.first ?? destination.name.lowercased()) + ":")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DS.accentSoft, in: .rect(cornerRadius: 8))
            }
            .padding(.horizontal, DS.space24)
            .padding(.vertical, DS.space16)
        } else {
            HStack {
                Text("No Lane Selected")
                    .font(DS.title1)
                    .foregroundStyle(DS.text)
                Spacer()
            }
            .padding(DS.space24)
        }
    }

    private var captureList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.selectedItems) { item in
                    CaptureLaneItemCard(
                        item: item,
                        attachments: viewModel.attachmentsByItemId[item.uuid] ?? []
                    )
                    .padding(.horizontal, DS.space24)
                }
            }
            .padding(.vertical, DS.space16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 40))
                .foregroundStyle(DS.textMuted)
            Text(viewModel.selectedDestination == nil ? "Create a lane to start capturing" : "This lane is waiting")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text(emptyStateSubtitle)
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateSubtitle: String {
        guard let destination = viewModel.selectedDestination else {
            return "Custom lanes give Telegram messages a precise destination."
        }
        let alias = destination.aliases.first ?? CaptureDestination.normalizeAlias(destination.name)
        return "Send “\(alias): …” from Telegram, or attach media with that caption."
    }
}

private struct CaptureLaneSidebarRow: View {
    let destination: CaptureDestination
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: destination.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? DS.textOnAccent : DS.textSecondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? DS.textOnAccent : DS.text)
                        .lineLimit(1)
                    Text(destination.type.displayName)
                        .font(DS.caption)
                        .foregroundStyle(isSelected ? DS.textOnAccent.opacity(0.78) : DS.textMuted)
                }

                Spacer()

                if destination.itemCount > 0 {
                    Text("\(destination.itemCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? DS.textOnAccent : DS.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? DS.accent : DS.surfaceHover.opacity(0.001), in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct CaptureLaneItemCard: View {
    let item: CapturedItem
    let attachments: [MediaAttachment]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            mediaPreview
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(itemTitle)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)
                    Spacer()
                    statusChip
                }
                if let detail = itemDetail {
                    Text(detail)
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(3)
                }
                HStack(spacing: 10) {
                    Label("Telegram", systemImage: "paperplane")
                    Text(relativeDate)
                    if !attachments.isEmpty {
                        Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                    }
                }
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            }
        }
        .padding(12)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if let thumbnail = attachments.compactMap(\.thumbnailPath).first,
           let image = NSImage(contentsOfFile: thumbnail) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 7))
        } else if let first = attachments.first {
            Image(systemName: icon(for: first.kind))
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DS.accent)
                .frame(width: 72, height: 72)
                .background(DS.accentSoft, in: .rect(cornerRadius: 7))
        } else {
            Image(systemName: "text.alignleft")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .frame(width: 72, height: 72)
                .background(DS.surface, in: .rect(cornerRadius: 7))
        }
    }

    private var statusChip: some View {
        Text(item.status.rawValue.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(item.status == .failed ? DS.red : DS.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.surface, in: .rect(cornerRadius: 7))
    }

    private var itemTitle: String {
        item.cleanText?.isEmpty == false ? item.cleanText! : item.caption ?? "Media capture"
    }

    private var itemDetail: String? {
        if let first = attachments.first {
            return "\(first.kind.displayName) · \(first.processingStatus.displayName)"
        }
        return item.parsedIntent
    }

    private var relativeDate: String {
        guard let date = ISO8601DateFormatter().date(from: item.createdAt) else { return item.createdAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func icon(for kind: MediaAttachmentKind) -> String {
        switch kind {
        case .image, .screenshot: return "photo"
        case .pdf: return "doc.richtext"
        case .audio: return "waveform"
        case .video: return "film"
        case .markdown, .textFile: return "doc.text"
        case .epub: return "book.closed"
        case .document, .unknown: return "doc"
        }
    }
}
