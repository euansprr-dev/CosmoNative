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
    static func open(uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid, "asPane": true]
        )
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

    @Environment(\.connectionLinkTargets) private var linkTargets

    var body: some View {
        Text(attributed)
            .font(font)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "cosmo", url.host == "connection" else { return .systemAction }
                let uuid = url.lastPathComponent
                guard !uuid.isEmpty else { return .discarded }
                ConnectionLinkOpener.open(uuid: uuid)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color
        guard !linkTargets.isEmpty else { return result }
        var claimed: [Range<AttributedString.Index>] = []
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
