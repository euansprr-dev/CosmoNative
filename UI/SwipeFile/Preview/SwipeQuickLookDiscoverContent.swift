import SwiftUI

/// Discover variant of the quick look: author + metric tiles + caption, with
/// Save (board menu) and Transcript as the primary path into Swipe Study.
struct SwipeQuickLookDiscoverContent: View {
    let post: SocialPostSnapshot
    let model: SwipeCardModel
    var hasPrevious = false
    var hasNext = false
    let onSave: (String?) -> Void
    let onTranscript: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                SwipeQuickLookDiscoverBody(post: post, model: model)
                    .id(post.id)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.12), value: post.id)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: post.platform.iconName)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(post.platform.swipeBrandColor)
                    .accessibilityHidden(true)
                Text(post.platform.displayName)
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
            navButton("chevron.left", help: "Previous (←)", enabled: hasPrevious, shortcut: .leftArrow, action: onPrevious)
            navButton("chevron.right", help: "Next (→)", enabled: hasNext, shortcut: .rightArrow, action: onNext)
            SwipeQuickLookIconButton(systemImage: "safari", help: "Open original post") {
                NSWorkspace.shared.open(post.canonicalURL)
            }
            SwipeQuickLookIconButton(systemImage: "xmark", help: "Close (Esc)", action: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func navButton(
        _ systemImage: String,
        help: String,
        enabled: Bool,
        shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        SwipeQuickLookIconButton(systemImage: systemImage, help: help, action: action)
            .keyboardShortcut(shortcut, modifiers: [])
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            saveMenu
            Button(action: onTranscript) {
                HStack(spacing: 7) {
                    Image(systemName: "text.quote")
                        .font(DS.caption.weight(.bold))
                    Text("Transcript & Study")
                        .font(DS.callout.weight(.semibold))
                    Text("⏎")
                        .font(DS.caption)
                        .opacity(0.7)
                }
                .foregroundStyle(DS.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(DS.glassInputFill))
                .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .help("Save and open in Swipe Study (⏎)")

            Spacer()

            Text("← → next · esc close")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.glassBorder).frame(height: 0.5)
        }
    }

    private var saveMenu: some View {
        Menu {
            Button("All Swipes", systemImage: "rectangle.stack.badge.plus") { onSave(nil) }
            if !SwipeBoardStore.shared.boards.isEmpty {
                Divider()
                ForEach(SwipeBoardStore.shared.boards) { board in
                    Button(board.name, systemImage: board.icon) { onSave(board.uuid) }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "bookmark.fill")
                    .font(DS.caption.weight(.bold))
                Text("Save")
                    .font(DS.callout.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(DS.caption2.weight(.semibold))
                    .opacity(0.8)
            }
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(DS.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Save to your swipe file")
        .accessibilityLabel("Save to board")
    }
}

// MARK: - Scrollable body

private struct SwipeQuickLookDiscoverBody: View {
    let post: SocialPostSnapshot
    let model: SwipeCardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                media
                authorRow
                metricTiles
                captionSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var media: some View {
        if model.aspect == .paper {
            Text(model.paperText ?? model.hookText)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            CachedAsyncImage(url: model.mediaURL, stableKey: model.mediaStableKey) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .empty, .failure:
                    Rectangle()
                        .fill(DS.glassSectionFill)
                        .overlay {
                            Image(systemName: post.platform.iconName)
                                .font(DS.title2)
                                .foregroundStyle(DS.textMuted)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let outlier = model.outlierLabel {
                    Text(outlier)
                        .font(DS.caption.weight(.bold))
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(DS.accent, in: Capsule())
                        .padding(10)
                }
            }
            .accessibilityLabel("Post media preview")
        }
    }

    private var authorRow: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: post.author.avatarURL, stableKey: "avatar-\(post.author.platformID)") { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty, .failure:
                    Circle().fill(DS.glassSectionFill)
                        .overlay {
                            Text(String(post.author.displayName.prefix(1)))
                                .font(DS.subheadline.weight(.semibold))
                                .foregroundStyle(DS.textMuted)
                        }
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(post.author.displayName)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                Text(authorMeta)
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var authorMeta: String {
        var parts = ["@\(post.author.handle)"]
        if let followers = post.author.followerCount {
            parts.append("\(SwipeFormatting.count(followers)) followers")
        }
        if let age = model.ageLabel {
            parts.append(age)
        }
        return parts.joined(separator: " · ")
    }

    private var metricTiles: some View {
        HStack(spacing: 8) {
            if let outlier = model.outlierLabel { metricTile(outlier, label: "outlier") }
            if let views = post.metrics.views { metricTile(SwipeFormatting.count(views), label: "views") }
            if let likes = post.metrics.likes { metricTile(SwipeFormatting.count(likes), label: "likes") }
            if let comments = post.metrics.comments { metricTile(SwipeFormatting.count(comments), label: "comments") }
            if let rate = post.derived.engagementRate { metricTile(SwipeFormatting.engagementRate(rate), label: "engagement") }
        }
    }

    private func metricTile(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.headline.monospacedDigit())
                .foregroundStyle(DS.text)
            Text(label)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var captionSection: some View {
        if model.aspect != .paper, let body = post.body, !body.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Caption")
                        .font(DS.caption.weight(.bold))
                        .foregroundStyle(DS.textMuted)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(body, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Copy caption")
                    .accessibilityLabel("Copy caption")
                }
                Text(body)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
    }
}
