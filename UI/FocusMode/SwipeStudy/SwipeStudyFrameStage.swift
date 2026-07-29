// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyFrameStage.swift
// The frame stage: a screenshot set, paged. Deliberately the same grammar as
// the carousel pager beside it (arrows on hover, page line beneath, letterboxed
// on media black) — a set of saved screenshots and a saved carousel are the
// same object shape, so they must read as the same object.
//
// Screenshots letterbox with scaledToFit on black, never scaledToFill: a
// screenshot's whole value is its composition, and cropping one to fill a
// frame throws away the thing you saved it for.

import SwiftUI
import AppKit

struct SwipeStudyFrameStage: View {
    let units: [SwipeArtifactUnit]

    @State private var index = 0
    @State private var isHovered = false
    @State private var attachments: [String: MediaAttachment] = [:]

    private var safeIndex: Int { min(max(index, 0), max(units.count - 1, 0)) }

    var body: some View {
        VStack(spacing: DS.space8) {
            frame
            if units.count > 1 { pageLine }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .task(id: units.map(\.attachmentUUID).compactMap { $0 }.joined()) {
            await loadAttachments()
        }
    }

    // MARK: - Frame

    private var frame: some View {
        ZStack {
            // Media black, never a warm fill: a screenshot's own background is
            // usually white, and a white gutter around a white screenshot is
            // indistinguishable from a broken layout.
            Rectangle().fill(.black)

            if let unit = units[safe: safeIndex] {
                if let attachment = unit.attachmentUUID.flatMap({ attachments[$0] }) {
                    SwipeStudyFrameImage(attachment: attachment)
                } else {
                    placeholder
                }
            }
        }
        .aspectRatio(stageAspect, contentMode: .fit)
        .clipShape(.rect(cornerRadius: DS.radiusLarge, style: .continuous))
        .overlay(alignment: .center) {
            if units.count > 1, isHovered { arrows }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    /// The stage takes the current frame's own aspect when we know it, so a
    /// tall phone screenshot gets a tall stage and a wide one gets a wide
    /// stage — the edge-to-edge honesty law from the preview rail.
    private var stageAspect: CGFloat {
        if let ratio = units[safe: safeIndex]?.aspectRatio, ratio > 0.05, ratio < 20 {
            return CGFloat(ratio)
        }
        return 4.0 / 5.0
    }

    private var placeholder: some View {
        Image(systemName: SwipeKind.frame.iconName)
            .font(DS.title2)
            .foregroundStyle(DS.textMuted)
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        guard units.count > 1 else { return "Screenshot" }
        return "Screenshot \(safeIndex + 1) of \(units.count)"
    }

    // MARK: - Paging

    private var arrows: some View {
        HStack {
            arrow("chevron.left", label: "Previous screenshot", enabled: safeIndex > 0) {
                step(-1)
            }
            Spacer(minLength: 0)
            arrow("chevron.right", label: "Next screenshot", enabled: safeIndex < units.count - 1) {
                step(1)
            }
        }
        .padding(.horizontal, DS.space12)
        .transition(.opacity)
    }

    private func arrow(
        _ systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.22)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private var pageLine: some View {
        Text("\(safeIndex + 1) / \(units.count)")
            .font(DS.caption.monospacedDigit())
            .foregroundStyle(DS.textMuted)
            .contentTransition(.numericText())
            .accessibilityHidden(true)
    }

    private func step(_ delta: Int) {
        let next = safeIndex + delta
        guard units.indices.contains(next) else { return }
        withAnimation(ProMotionSprings.snappy) { index = next }
    }

    // MARK: - Loading

    private func loadAttachments() async {
        let uuids = units.compactMap(\.attachmentUUID)
        guard !uuids.isEmpty else { return }
        let rows = (try? await MediaAttachmentRepository.shared.fetch(uuids: uuids)) ?? []
        attachments = Dictionary(rows.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - One frame

/// Full-resolution original (not the thumbnail): the Study bench is where you
/// read the copy off a screenshot, so a 600px thumb is not enough.
private struct SwipeStudyFrameImage: View {
    let attachment: MediaAttachment

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: attachment.uuid) {
            guard image == nil else { return }
            if let url = await AttachmentCloudStore.shared.localOriginalURL(for: attachment),
               let loaded = NSImage(contentsOf: url) {
                image = loaded
            }
        }
        .accessibilityHidden(true)
    }
}
