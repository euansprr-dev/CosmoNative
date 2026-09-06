// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyPageStage.swift
// The page stage: a captured sales page as a tall scroller with a section rail
// down its edge.
//
// A page is read by SCROLLING, so the stage scrolls — it is not a pager. The
// rail is what makes it studyable rather than just long: each mark is a
// section, tinted by role family, and tapping one scrolls the page to it. That
// is the same two-way binding the reel's speech-segment rows already have, and
// it is what turns "a screenshot of a long page" into an anatomy you can walk.

import SwiftUI
import AppKit

struct SwipeStudyPageStage: View {
    let units: [SwipeArtifactUnit]
    /// Scroll target published by the manuscript when a unit row is clicked.
    @Binding var focusedUnitID: String?

    @State private var attachments: [String: MediaAttachment] = [:]
    @State private var hoveredUnitID: String?

    private var orderedUnits: [SwipeArtifactUnit] {
        units.sorted { $0.index < $1.index }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.space8) {
            sectionRail
            pageScroller
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: orderedUnits.compactMap(\.attachmentUUID).joined()) {
            await loadAttachments()
        }
    }

    // MARK: - The page

    private var pageScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(orderedUnits) { unit in
                        sliceView(unit)
                            .id(unit.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 620)
            .clipShape(.rect(cornerRadius: DS.radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                    .strokeBorder(DS.glassBorder, lineWidth: 0.5)
            )
            .onChange(of: focusedUnitID) { _, id in
                guard let id else { return }
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }

    /// Slices butt against each other with no gap and no corner radius — they
    /// are one continuous page, and any seam treatment would read as a stack
    /// of cards rather than the document it is.
    private func sliceView(_ unit: SwipeArtifactUnit) -> some View {
        ZStack(alignment: .topLeading) {
            if let attachment = unit.attachmentUUID.flatMap({ attachments[$0] }) {
                SwipeStudySliceImage(attachment: attachment)
            } else {
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .frame(height: 160)
            }
        }
        .overlay(alignment: .topLeading) {
            if let role = unit.role, hoveredUnitID == unit.id {
                roleChip(role)
                    .padding(DS.space8)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                hoveredUnitID = hovering ? unit.id : nil
            }
        }
        .onTapGesture { focusedUnitID = unit.id }
        .accessibilityLabel(unit.role.map { "\($0.displayName) section" } ?? "Page section")
    }

    private func roleChip(_ role: SwipeUnitRole) -> some View {
        Text(role.displayName)
            .font(DS.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(.black.opacity(0.55), in: Capsule())
    }

    // MARK: - Section rail

    /// The page's anatomy at a glance: one mark per section, height-weighted
    /// so the rail is a true map of the scroll. This is the whole reason a
    /// page swipe is studyable — you can see the offer sits two thirds down
    /// and the CTA repeats four times without reading a word.
    private var sectionRail: some View {
        VStack(spacing: 2) {
            ForEach(orderedUnits) { unit in
                railMark(unit)
            }
        }
        .frame(width: 6)
        .frame(maxHeight: 620)
        .accessibilityHidden(true)
    }

    private func railMark(_ unit: SwipeArtifactUnit) -> some View {
        let isFocused = focusedUnitID == unit.id || hoveredUnitID == unit.id
        return Capsule()
            .fill(railTint(unit.role).opacity(isFocused ? 1 : 0.45))
            .frame(height: max(6, railHeight(unit)))
            .onTapGesture {
                withAnimation(ProMotionSprings.snappy) { focusedUnitID = unit.id }
            }
            .onHover { hovering in
                withAnimation(ProMotionSprings.hover) {
                    hoveredUnitID = hovering ? unit.id : nil
                }
            }
    }

    /// Role FAMILY, not role: a colour per role on a 6pt rail is confetti. Five
    /// families read as a structure — opening, body, belief, commerce, close.
    private func railTint(_ role: SwipeUnitRole?) -> Color {
        switch role?.family {
        case .opening: return DS.entityIdea
        case .body: return DS.entityResearch
        case .belief: return DS.entityConnection
        case .commerce: return DS.accent
        case .close: return DS.gilt
        case .other, .none: return DS.textMuted
        }
    }

    private func railHeight(_ unit: SwipeArtifactUnit) -> CGFloat {
        let total = orderedUnits.reduce(0) { $0 + max(1, sectionWeight($1)) }
        guard total > 0 else { return 12 }
        return 620 * (max(1, sectionWeight(unit)) / total)
    }

    /// Aspect ratio carries the slice's true height at capture width, which is
    /// what makes the rail proportional to the real scroll rather than to the
    /// section count.
    private func sectionWeight(_ unit: SwipeArtifactUnit) -> CGFloat {
        guard let ratio = unit.aspectRatio, ratio > 0 else { return 1 }
        return CGFloat(1 / ratio)
    }

    // MARK: - Loading

    private func loadAttachments() async {
        let uuids = orderedUnits.compactMap(\.attachmentUUID)
        guard !uuids.isEmpty else { return }
        let rows = (try? await MediaAttachmentRepository.shared.fetch(uuids: uuids)) ?? []
        attachments = Dictionary(rows.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - One slice

/// A page slice at its honest height. `scaledToFit` at full width means the
/// stack reconstructs the original page exactly, seam to seam.
private struct SwipeStudySliceImage: View {
    let attachment: MediaAttachment

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .imageSaveAffordance(ImageSaveRequest(.attachment(attachment)))
            } else {
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .frame(height: 160)
            }
        }
        .task(id: attachment.uuid) {
            // NO `guard image == nil`: SwiftUI reuses this view when the pager
            // moves to a different attachment, so the old image is still in
            // @State. Guarding on it made the page counter advance while the
            // picture never changed. Clearing first also gives the loading
            // state something honest to show.
            image = nil
            guard let url = await AttachmentCloudStore.shared.localOriginalURL(for: attachment),
                  !Task.isCancelled else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .accessibilityHidden(true)
    }
}
