// CosmoOS/UI/FocusMode/Connection/ConnectionLinkedText.swift
// Cross-connection hyperlinks: the shared pill for reference rows that link
// to another Connection page, and render-time inline linking — occurrences of
// sibling page titles inside item text become tappable runs that open the
// target as a pane. Matching happens at render time against the deep dive's
// current pages, so yesterday's text lights up the moment a page exists —
// no data rewrite, retroactive by construction.

import SwiftUI

// MARK: - Link targets (sibling pages of the same deep dive)

struct ConnectionLinkTargets: Equatable {
    struct Target: Equatable {
        var uuid: String
        var title: String
    }
    var targets: [Target] = []

    static let empty = ConnectionLinkTargets()

    init(targets: [Target] = []) {
        // Longest titles first so "Box breathing" wins over "Breathing".
        self.targets = targets
            .filter { $0.title.count >= 4 }
            .sorted { $0.title.count > $1.title.count }
    }

    var isEmpty: Bool { targets.isEmpty }

    func title(for uuid: String) -> String? {
        targets.first { $0.uuid == uuid }?.title
    }
}

extension EnvironmentValues {
    @Entry var connectionLinkTargets: ConnectionLinkTargets = .empty
}

// MARK: - Navigation

enum ConnectionLinkOpener {
    /// Opens the linked Connection page as a pane beside the current one.
    /// (The handler fetches by uuid and routes by type, so any mentioned atom
    /// — note, idea, research — opens the same way.)
    static func open(uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid, "asPane": true]
        )
    }

    /// True for the URLs the concept views mint for links they own.
    static func uuid(from url: URL) -> String? {
        guard url.scheme == "cosmo",
              url.host == "connection" || url.host == "atom" else { return nil }
        let uuid = url.lastPathComponent
        return uuid.isEmpty ? nil : uuid
    }

    static func url(for mention: RichMention) -> URL? {
        let host = mention.entityType == .connection ? "connection" : "atom"
        return URL(string: "cosmo://\(host)/\(mention.entityUUID)")
    }
}

// MARK: - Link pill (reference rows)

/// Purple connection pill for a reference row that links to another page.
struct ConnectionLinkPill: View {
    let title: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(CosmoTypography.labelSmall)
                    .lineLimit(1)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 7, weight: .semibold))
                    .opacity(isHovered ? 1 : 0.45)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(CosmoMentionColors.connection)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 3)
            .background(CosmoMentionColors.connection.opacity(isHovered ? 0.16 : 0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(CosmoMentionColors.connection.opacity(0.28), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Open \(title) as a pane")
        .accessibilityLabel("Open linked concept \(title)")
    }
}

// MARK: - Inline linked text (item bodies)

/// Item text whose mentions of sibling Connection pages are tappable links
/// that open the mentioned page as a pane.
struct ConnectionLinkedText: View {
    let text: String
    var font: Font = DS.body
    var color: Color = DS.text
    /// Explicit mentions persisted on the item (@ menu picks, collaborator
    /// tokens) — their "@Title" runs link in the entity's tint, regardless of
    /// whether the target is a sibling of this deep dive.
    var mentions: [RichMention] = []
    var lineLimit: Int? = nil

    @Environment(\.connectionLinkTargets) private var linkTargets

    var body: some View {
        Text(attributed)
            .font(font)
            .textSelection(.enabled)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: lineLimit == nil)
            .environment(\.openURL, OpenURLAction { url in
                guard let uuid = ConnectionLinkOpener.uuid(from: url) else { return .systemAction }
                ConnectionLinkOpener.open(uuid: uuid)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color
        var claimed: [Range<AttributedString.Index>] = []

        // Explicit mentions claim first — they are stored facts, not
        // render-time title guesses.
        for mention in mentions {
            guard let range = result.range(of: mention.displayText),
                  !claimed.contains(where: { $0.overlaps(range) }),
                  let url = ConnectionLinkOpener.url(for: mention) else { continue }
            result[range].link = url
            result[range].foregroundColor = CosmoMentionColors.color(for: mention.entityType)
            result[range].underlineStyle = .single
            claimed.append(range)
        }

        guard !linkTargets.isEmpty else { return result }
        for target in linkTargets.targets {
            guard let range = result.range(of: target.title, options: [.caseInsensitive]),
                  !claimed.contains(where: { $0.overlaps(range) }),
                  let url = URL(string: "cosmo://connection/\(target.uuid)") else { continue }
            result[range].link = url
            result[range].foregroundColor = CosmoMentionColors.connection
            result[range].underlineStyle = .single
            claimed.append(range)
        }
        return result
    }
}
