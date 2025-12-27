// CosmoOS/Canvas/ResearchBlockView.swift
// Green-accented Research block for Thinkspace canvas
// Dark glass design matching Sanctuary aesthetic
// December 2025 - Shows actual research content with metadata

import SwiftUI

struct ResearchBlockView: View {
    let block: CanvasBlock

    @State private var isExpanded = false
    @State private var atom: Atom?
    @State private var isLoading = true
    @EnvironmentObject private var expansionManager: BlockExpansionManager

    // Green accent for research
    private let accentColor = CosmoColors.blockResearch

    // Parsed metadata
    private var platform: String? {
        guard let structured = atom?.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block.metadata["platform"]
        }
        return json["platform"] as? String ?? json["source_type"] as? String
    }

    private var author: String? {
        guard let structured = atom?.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block.metadata["author"]
        }
        return json["author"] as? String ?? json["channel"] as? String
    }

    private var duration: String? {
        guard let structured = atom?.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block.metadata["duration"]
        }
        return json["duration"] as? String ?? json["duration_string"] as? String
    }

    private var thumbnailURL: String? {
        guard let structured = atom?.structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block.metadata["thumbnail"]
        }
        return json["thumbnail_url"] as? String ?? json["thumbnail"] as? String
    }

    private var contentType: String {
        let url = block.metadata["url"]?.lowercased() ?? ""
        if url.contains("youtube") || url.contains("youtu.be") || url.contains("vimeo") || url.contains("loom") {
            return "Video"
        } else if url.hasSuffix(".pdf") {
            return "PDF"
        } else if url.contains("twitter") || url.contains("x.com") || url.contains("linkedin") {
            return "Social"
        } else if !url.isEmpty {
            return "Article"
        }
        return "Research"
    }

    var body: some View {
        CosmoBlockWrapper(
            block: block,
            accentColor: accentColor,
            icon: "magnifyingglass",
            title: block.title,
            isExpanded: $isExpanded,
            onFocusMode: openFocusMode
        ) {
            researchContent
        }
        .onAppear {
            loadAtom()
        }
    }

    // MARK: - Research Content

    private var researchContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and metadata
            HStack(spacing: 12) {
                // Thumbnail or icon
                thumbnailView
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    // Content type badge
                    Text(contentType.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accentColor)
                        .tracking(0.8)

                    // Title
                    Text(block.title.isEmpty ? "Untitled Research" : block.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Metadata row
                    metadataRow
                }

                Spacer()
            }

            // Body preview
            if let body = atom?.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(isExpanded ? 6 : 3)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(accentColor)
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }

            Spacer()

            // Footer
            HStack {
                // URL indicator
                if let url = block.metadata["url"], !url.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text(extractDomain(from: url))
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundColor(accentColor.opacity(0.7))
                }

                Spacer()

                // Timestamp
                if let created = block.metadata["created"] {
                    Text(formatTimestamp(created))
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.3))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private var thumbnailView: some View {
        if let urlString = thumbnailURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure, .empty:
                    iconPlaceholder
                @unknown default:
                    iconPlaceholder
                }
            }
        } else {
            iconPlaceholder
        }
    }

    private var iconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(accentColor.opacity(0.15))

            Image(systemName: contentTypeIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(accentColor)
        }
    }

    private var contentTypeIcon: String {
        switch contentType {
        case "Video": return "play.rectangle.fill"
        case "PDF": return "doc.text.fill"
        case "Social": return "bubble.left.and.bubble.right.fill"
        case "Article": return "doc.richtext.fill"
        default: return "magnifyingglass"
        }
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let author = author {
                Text(author)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
            }

            if let platform = platform {
                if author != nil {
                    Text("·")
                        .foregroundColor(Color.white.opacity(0.3))
                }
                Text(platform)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            if let duration = duration {
                Text("·")
                    .foregroundColor(Color.white.opacity(0.3))
                Text(duration)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
            }
        }
    }

    // MARK: - Data Loading

    private func loadAtom() {
        Task {
            if let loaded = try? await AtomRepository.shared.fetch(id: block.entityId) {
                await MainActor.run {
                    atom = loaded
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Focus Mode

    private func openFocusMode() {
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "type": EntityType.research,
                "id": block.entityId
            ]
        )
    }

    // MARK: - Helpers

    private func formatTimestamp(_ timestamp: String) -> String {
        if let date = ISO8601DateFormatter().date(from: timestamp) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }

    private func extractDomain(from url: String) -> String {
        guard let urlObj = URL(string: url), let host = urlObj.host else {
            return url
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - Preview

#if DEBUG
struct ResearchBlockView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            ResearchBlockView(
                block: CanvasBlock(
                    position: CGPoint(x: 200, y: 200),
                    size: CGSize(width: 320, height: 280),
                    entityType: .research,
                    entityId: 1,
                    entityUuid: "preview",
                    title: "Dan Koe - How to Reinvent Your Life",
                    metadata: [
                        "url": "https://youtube.com/watch?v=example",
                        "platform": "YouTube",
                        "author": "Dan Koe",
                        "duration": "42:18"
                    ]
                )
            )
            .environmentObject(BlockExpansionManager())
        }
        .frame(width: 500, height: 400)
    }
}
#endif
