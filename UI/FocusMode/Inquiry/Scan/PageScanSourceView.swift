// CosmoOS/UI/FocusMode/Inquiry/Scan/PageScanSourceView.swift
// The reader for a page-scan source: the original pages on the left (the ink
// is the truth), the digitized layer on the right — per-page transcript and
// the extracts routed from it. Provenance runs both ways: select an extract
// and the handwritten lines it came from glow on the photo.

import AppKit
import SwiftUI

@MainActor
struct PageScanSourceView: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel
    let sourceUUID: String

    @State private var attachments: [MediaAttachment] = []
    @State private var extracts: [Atom] = []
    @State private var selectedPageIndex = 0
    @State private var highlightedExtractUUID: String?
    @State private var hoveredPageIndex: Int?

    var body: some View {
        HSplitView {
            pageColumn
                .frame(minWidth: 320, idealWidth: 460)
            digitizedColumn
                .frame(minWidth: 300, idealWidth: 380)
        }
        .background(DS.bg)
        .task(id: sourceUUID) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .cosmoMediaAttachmentArrived)) { _ in
            Task { await load() }
        }
    }

    // MARK: - Load

    private func load() async {
        guard let source = try? await AtomRepository.shared.fetch(uuid: sourceUUID) else { return }
        let uuids = (source.metadataDict?["attachmentUUIDs"] as? [String]) ?? []
        attachments = (try? await MediaAttachmentRepository.shared.fetch(uuids: uuids)) ?? []
        if selectedPageIndex >= attachments.count { selectedPageIndex = max(0, attachments.count - 1) }

        let all = (try? await InquiryRepository.shared.fetchExtracts(forDeepDive: viewModel.deepDive?.uuid ?? "")) ?? []
        extracts = all
            .filter { $0.extractMetadata?.sourceUUID == sourceUUID }
            .sorted { ($0.createdAt) < ($1.createdAt) }
    }

    // MARK: - Left: the original pages

    private var pageColumn: some View {
        VStack(spacing: 0) {
            ScanPageCanvas(
                attachment: attachments.indices.contains(selectedPageIndex) ? attachments[selectedPageIndex] : nil,
                highlightLines: highlightLines
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if attachments.count > 1 {
                pageStrip
            }
        }
        .background(DS.documentSurface)
    }

    /// Lines to glow on the selected page — the highlighted extract's ink.
    private var highlightLines: [VisionPageOCR.Line] {
        guard let highlightedExtractUUID,
              let extract = extracts.first(where: { $0.uuid == highlightedExtractUUID }),
              attachments.indices.contains(selectedPageIndex) else { return [] }
        let attachment = attachments[selectedPageIndex]
        // Only pages this extract actually came from.
        if let owned = extract.extractMetadata?.attachmentUUIDs, !owned.isEmpty,
           !owned.contains(attachment.uuid) {
            return []
        }
        let lines = VisionPageOCR.decodeLines(fromMetadataValue: attachment.metadataValueAny("visionLines"))
        return VisionPageOCR.matchingLines(for: extract.body ?? "", in: lines)
    }

    private var pageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space6) {
                ForEach(Array(attachments.enumerated()), id: \.element.uuid) { index, attachment in
                    Button {
                        withAnimation(ProMotionSprings.snappy) { selectedPageIndex = index }
                    } label: {
                        AttachmentThumbnailView(attachment: attachment, cornerRadius: 6)
                            .frame(width: 44, height: 58)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(index == selectedPageIndex ? DS.accent : .clear, lineWidth: 1.5)
                            )
                            .scaleEffect(hoveredPageIndex == index ? 1.01 : 1)
                            .shadow(
                                color: .black.opacity(hoveredPageIndex == index ? 0.14 : 0),
                                radius: 5, y: 2
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(ProMotionSprings.hover) {
                            hoveredPageIndex = hovering ? index : nil
                        }
                    }
                    .help("Page \(index + 1)")
                    .accessibilityLabel("Page \(index + 1) of \(attachments.count)")
                    .accessibilityAddTraits(index == selectedPageIndex ? [.isSelected] : [])
                }
            }
            .padding(DS.space8)
        }
        .background(DS.glassSectionFill)
    }

    // MARK: - Right: the digitized layer

    private var digitizedColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                transcriptSection
                extractsSection
            }
            .padding(DS.space16)
        }
        .background(DS.bg)
    }

    @ViewBuilder
    private var transcriptSection: some View {
        let attachment = attachments.indices.contains(selectedPageIndex) ? attachments[selectedPageIndex] : nil
        VStack(alignment: .leading, spacing: DS.space8) {
            sectionLabel("TRANSCRIPT", count: nil)
            if let transcript = attachment?.transcriptText ?? attachment?.extractedText,
               !transcript.isEmpty {
                Text(transcript)
                    .font(DS.body)
                    .foregroundStyle(DS.text.opacity(0.9))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Still reading this page…", systemImage: "sparkles")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private var extractsSection: some View {
        if !extracts.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                sectionLabel("ROUTED THOUGHTS", count: extracts.count)
                ForEach(extracts, id: \.uuid) { extract in
                    extractRow(extract)
                }
            }
        }
    }

    private func extractRow(_ extract: Atom) -> some View {
        ScanExtractRow(
            extract: extract,
            isHighlighted: highlightedExtractUUID == extract.uuid
        ) {
            withAnimation(ProMotionSprings.snappy) {
                highlightedExtractUUID = highlightedExtractUUID == extract.uuid ? nil : extract.uuid
            }
        }
    }

    private func sectionLabel(_ label: String, count: Int?) -> some View {
        HStack(spacing: DS.space6) {
            Text(label)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.gilt)
                .kerning(0.8)
            Spacer(minLength: 0)
            if let count {
                Text("\(count)")
                    .font(DS.caption2.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
        }
    }
}

// MARK: - One routed thought (hover-lit, selectable for provenance)

private struct ScanExtractRow: View {
    let extract: Atom
    let isHighlighted: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DS.space4) {
                HStack(spacing: DS.space6) {
                    Text(extract.extractMetadata?.kind.displayName ?? "Note")
                        .font(DS.caption2.weight(.semibold))
                        .foregroundStyle(isHighlighted ? DS.accent : DS.textSecondary)
                    Spacer(minLength: 0)
                }
                Text(extract.body ?? "")
                    .font(DS.callout)
                    .foregroundStyle(DS.text.opacity(0.9))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(DS.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHighlighted
                    ? AnyShapeStyle(DS.accentSoft)
                    : AnyShapeStyle(isHovered ? DS.glassCardFill : DS.glassSectionFill),
                in: .rect(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHighlighted ? DS.accent.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(.rect(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Show where this was written on the page")
        .accessibilityLabel("\(extract.extractMetadata?.kind.displayName ?? "Note"): \(String((extract.body ?? "").prefix(80)))")
        .accessibilityAddTraits(isHighlighted ? [.isSelected] : [])
    }
}

// MARK: - The page canvas (original + provenance glow)

private struct ScanPageCanvas: View {
    let attachment: MediaAttachment?
    let highlightLines: [VisionPageOCR.Line]

    @State private var image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    let fitted = fittedRect(imageSize: image.size, in: proxy.size)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .overlay {
                            ForEach(Array(highlightLines.enumerated()), id: \.offset) { _, line in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(DS.accent.opacity(0.18))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .stroke(DS.accent.opacity(0.55), lineWidth: 1)
                                    )
                                    .frame(
                                        width: fitted.width * line.width + 8,
                                        height: fitted.height * line.height + 6
                                    )
                                    .position(
                                        x: fitted.minX + fitted.width * (line.x + line.width / 2),
                                        y: fitted.minY + fitted.height * (line.y + line.height / 2)
                                    )
                            }
                        }
                } else {
                    ProgressView()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .padding(DS.space12)
        .animation(ProMotionSprings.gentle, value: highlightLines)
        .task(id: attachment?.uuid) {
            image = nil
            guard let attachment else { return }
            if let url = await AttachmentCloudStore.shared.localOriginalURL(for: attachment) {
                image = NSImage(contentsOf: url)
            }
        }
    }

    /// Where the scaled-to-fit image actually sits inside the canvas.
    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private extension MediaAttachment {
    /// Raw metadata value (any JSON type) — the String-typed helper in
    /// AttachmentCloudStore covers strings only.
    func metadataValueAny(_ key: String) -> Any? {
        guard let metadata, let data = metadata.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict[key]
    }
}
