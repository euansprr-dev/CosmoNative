// CosmoOS/Components/AttachmentViews.swift
// Rendering for captured-page attachments on the Mac: a single thumbnail, a
// rail of them, and the page viewer sheet. Bytes resolve through
// AttachmentCloudStore (local capture → cache → authed cloud download), so
// the same views work for pages captured on either device.

import AppKit
import SwiftUI

// MARK: - One thumbnail

struct AttachmentThumbnailView: View {
    let attachment: MediaAttachment
    var cornerRadius: CGFloat = 8

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .overlay(
                        Image(systemName: "doc.text.image")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    )
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
        .task(id: attachment.uuid) {
            guard image == nil else { return }
            if let url = await AttachmentCloudStore.shared.localThumbnailURL(for: attachment),
               let loaded = NSImage(contentsOf: url) {
                image = loaded
            }
        }
    }
}

// MARK: - Rail (inbox inspector, detail surfaces)

/// A horizontal rail of page originals; click opens the page viewer sheet.
struct AttachmentRail: View {
    let attachmentUUIDs: [String]
    var thumbSize: CGSize = CGSize(width: 76, height: 100)

    @State private var attachments: [MediaAttachment] = []
    @State private var viewerIndex: Int?
    @State private var hoveredUUID: String?

    var body: some View {
        // Always render the rail's shape: skeleton pages while rows load
        // (a `.task` on a conditionally-empty view never fires), the real
        // thumbnails the moment they land.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space8) {
                if attachments.isEmpty {
                    ForEach(attachmentUUIDs, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DS.glassSectionFill)
                            .frame(width: thumbSize.width, height: thumbSize.height)
                    }
                } else {
                    ForEach(Array(attachments.enumerated()), id: \.element.uuid) { index, attachment in
                        Button {
                            viewerIndex = index
                        } label: {
                            AttachmentThumbnailView(attachment: attachment)
                                .frame(width: thumbSize.width, height: thumbSize.height)
                                .scaleEffect(hoveredUUID == attachment.uuid ? 1.01 : 1)
                                .shadow(
                                    color: .black.opacity(hoveredUUID == attachment.uuid ? 0.14 : 0.06),
                                    radius: hoveredUUID == attachment.uuid ? 8 : 3,
                                    y: 2
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(ProMotionSprings.hover) {
                                hoveredUUID = hovering ? attachment.uuid : nil
                            }
                        }
                        .help("Open the original (page \(index + 1) of \(attachments.count))")
                        .accessibilityLabel("Page \(index + 1) of \(attachments.count)")
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .animation(ProMotionSprings.gentle, value: attachments.map(\.uuid))
        .task(id: attachmentUUIDs) {
            guard !attachmentUUIDs.isEmpty else {
                attachments = []
                return
            }
            attachments = (try? await MediaAttachmentRepository.shared.fetch(uuids: attachmentUUIDs)) ?? []
        }
        .sheet(item: Binding(
            get: { viewerIndex.map(PageIndex.init(value:)) },
            set: { viewerIndex = $0?.value }
        )) { index in
            AttachmentPageViewer(attachments: attachments, initialIndex: index.value)
        }
    }

    private struct PageIndex: Identifiable {
        let value: Int
        var id: Int { value }
    }
}

// MARK: - Row thumb (inbox queue)

/// The row's mini original: first page as a small thumb, extra pages as a
/// monospaced count riding its corner.
struct InboxRowPageThumb: View {
    let firstAttachmentUUID: String
    let pageCount: Int

    @State private var attachment: MediaAttachment?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let attachment {
                AttachmentThumbnailView(attachment: attachment, cornerRadius: 5)
                    .frame(width: 30, height: 40)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(DS.glassSectionFill)
                    .frame(width: 30, height: 40)
            }

            if pageCount > 1 {
                Text("\(pageCount)")
                    .font(DS.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, 3)
                    .background(DS.glassCardFill, in: Capsule())
                    .offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
        .task(id: firstAttachmentUUID) {
            attachment = try? await MediaAttachmentRepository.shared.fetch(uuid: firstAttachmentUUID)
        }
    }
}

// MARK: - Page viewer sheet

/// The original, honored: pages at reading size with arrow-key paging.
/// Esc closes (sheet default).
struct AttachmentPageViewer: View {
    let attachments: [MediaAttachment]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pageSurface
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 560, idealHeight: 860)
        .background(DS.bg)
        .onAppear { index = initialIndex }
        .task(id: index) { await loadPage() }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
    }

    private var header: some View {
        HStack(spacing: DS.space12) {
            Text(attachments.count > 1 ? "Page \(index + 1) of \(attachments.count)" : "Original")
                .font(DS.headline)
                .foregroundStyle(DS.text)
                .monospacedDigit()
                .contentTransition(.numericText())

            Spacer()

            if attachments.count > 1 {
                Button { _ = step(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help("Previous page (←)")

                Button { _ = step(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(index == attachments.count - 1)
                .help("Next page (→)")
            }

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space12)
    }

    @ViewBuilder
    private var pageSurface: some View {
        if let image {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(DS.space16)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        let next = index + delta
        guard attachments.indices.contains(next) else { return .ignored }
        image = nil
        withAnimation(ProMotionSprings.snappy) { index = next }
        return .handled
    }

    private func loadPage() async {
        guard attachments.indices.contains(index) else { return }
        if let url = await AttachmentCloudStore.shared.localOriginalURL(for: attachments[index]),
           let loaded = NSImage(contentsOf: url) {
            image = loaded
        }
    }
}
