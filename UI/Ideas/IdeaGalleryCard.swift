import SwiftUI

/// An idea is a small working document. Its source is a reference, never its cover.
struct IdeaGalleryCard: View {
    let idea: IdeaGalleryItem
    let excerpt: String?
    let thumbnails: [String]
    let showsClient: Bool
    let selected: Bool
    let cursor: Bool
    let selectionCount: Int
    let actions: IdeaDeskActions
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onBegin: () -> Void
    let onBulkAssign: (String?) -> Void
    let onBulkArchive: () -> Void
    @State private var hovered = false
    @State private var choosingDate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onSelect) { document }
            .buttonStyle(IdeaDocumentButtonStyle())
            .simultaneousGesture(TapGesture(count: 2).onEnded(onOpen))
            .onHover { hovered = $0 }
            .contextMenu { menu }
            .popover(isPresented: $choosingDate) {
                ContentSchedulePopover(title: "Writing session · \(idea.title)", currentDay: nil,
                    onPick: { choosingDate = false; actions.schedule($0) })
            }
            .draggable(PipelineDropPayload.idea(idea.atomUUID).dragString)
            .help("\(idea.title) — double-click to open; Space to preview")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([idea.title, showsClient ? idea.clientName ?? "Personal" : nil, idea.isPinned ? "Pinned" : nil].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onSelect() }
            .accessibilityAction(named: "Preview", onPreview)
            .accessibilityAction(named: "Open", onOpen)
    }

    private var document: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            title
            substance
            Spacer(minLength: 0)
            footer
        }
        .padding(DS.space20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 232, alignment: .topLeading)
        .background(selected ? DS.accentSoft.opacity(0.5) : DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: DS.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .strokeBorder(cursor ? DS.focusRing : selected ? DS.accent.opacity(0.5) : DS.borderSubtle,
                              lineWidth: cursor || selected ? 1.5 : 0.75)
        }
        .shadow(color: DS.text.opacity(hovered ? 0.07 : 0.025), radius: hovered ? 10 : 3, y: hovered ? 3 : 1)
        .offset(y: hovered && !reduceMotion ? -2 : 0)
        .animation(reduceMotion ? nil : ProMotionSprings.hover, value: hovered)
        .contentShape(.rect(cornerRadius: DS.radiusLarge))
    }

    private var title: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Text(idea.title)
                .font(DS.title2).foregroundStyle(DS.text)
                .multilineTextAlignment(.leading).lineSpacing(2)
                .lineLimit(excerpt == nil ? (thumbnails.isEmpty ? 6 : 4) : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if idea.isPinned {
                Image(systemName: "pin.fill").font(DS.caption).foregroundStyle(DS.textMuted).padding(.top, DS.space4)
            }
        }
    }

    private var substance: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            if let excerpt {
                Text(excerpt).font(DS.callout).foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.leading).lineSpacing(3).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else { Spacer(minLength: 0) }
            if !thumbnails.isEmpty {
                IdeaInspirationThumb(candidates: thumbnails, hairline: DS.borderSubtle, width: 48, height: 60)
                    .id(idea.atomUUID + thumbnails.joined())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: DS.space6) {
            if showsClient {
                Circle().fill(idea.clientUUID.map { DS.clientColor(for: $0) } ?? DS.textMuted).frame(width: 5, height: 5)
                Text(idea.clientName ?? "Personal").lineLimit(1)
            } else if let format = idea.contentFormat {
                Text(format.displayName).lineLimit(1)
            } else if !thumbnails.isEmpty {
                Label("Linked source", systemImage: "link").lineLimit(1)
            }
            Spacer(minLength: DS.space4)
            if idea.contentCount > 0 {
                Label("\(idea.contentCount)", systemImage: "doc.on.doc").help("Used in \(idea.contentCount) content pieces")
            }
            if let date = ISO8601.date(from: idea.updatedAt) {
                Text(date.cosmoCompactAge).monospacedDigit()
            }
        }
        .font(DS.caption).foregroundStyle(DS.textMuted)
    }

    @ViewBuilder private var menu: some View {
        if selected && selectionCount > 1 {
            Menu("Assign \(selectionCount) ideas") { clientMenu(onBulkAssign) }
            Button(idea.status == .archived ? "Restore \(selectionCount) ideas" : "Archive \(selectionCount) ideas",
                   systemImage: idea.status == .archived ? "arrow.uturn.backward" : "archivebox", action: onBulkArchive)
        } else {
            Button("Open idea", systemImage: "arrow.up.left.and.arrow.down.right", action: onOpen)
            Button("Preview", systemImage: "eye", action: onPreview)
            Button("Open beside current work", systemImage: "rectangle.split.2x1", action: actions.openAsPane)
            Divider()
            if idea.status != .archived {
                Button("Begin writing", systemImage: "square.and.pencil", action: onBegin)
                Button(idea.isPinned ? "Unpin idea" : "Pin idea", systemImage: idea.isPinned ? "pin.slash" : "pin", action: actions.togglePin)
                Button("Book writing session…", systemImage: "calendar.badge.clock") { choosingDate = true }
            }
            Menu("Assign client") { clientMenu(actions.assignClient) }
            Divider()
            if idea.status == .archived {
                Button("Restore idea", systemImage: "arrow.uturn.backward") { actions.setStatus(.spark) }
                Button("Delete idea", systemImage: "trash", role: .destructive, action: actions.delete)
            } else {
                Button("Archive idea", systemImage: "archivebox", action: actions.pass)
            }
        }
    }

    private func clientMenu(_ assign: @escaping (String?) -> Void) -> some View {
        Group {
            Button("Personal") { assign(nil) }
            Divider()
            ForEach(actions.assignableClients, id: \.uuid) { client in Button(client.name) { assign(client.uuid) } }
        }
    }
}

private struct IdeaDocumentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : ProMotionSprings.press, value: configuration.isPressed)
    }
}
