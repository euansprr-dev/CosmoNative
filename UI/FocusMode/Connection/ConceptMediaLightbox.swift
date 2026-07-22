// CosmoOS/UI/FocusMode/Connection/ConceptMediaLightbox.swift
// The Stage: a scrim lightbox over the concept workspace showing one media
// ref as the hero. Atom-backed refs reuse the Swipe Study stage machinery
// (reel player with local cache, carousel pager, YouTube player) through a
// per-item SwipeStudyModel; owned assets render directly. All AV activity
// lives HERE — board tiles stay static.
// July 2026

import SwiftUI
import AVKit

struct ConceptMediaLightbox: View {
    /// Ordered media refs — arrow keys page through this list.
    let media: [ConnectionMediaItem]
    let atoms: [String: Atom]
    let presentedID: UUID
    let actions: ConnectionWorkspaceActions
    let onCaptionCommit: (UUID, String) -> Void
    let onPinMoment: (UUID, Double) -> Void
    /// Pull-quote capture: a transcript paragraph lands in a section as an
    /// item with full provenance (sourceAtomUUID + verbatim snippet).
    let onCaptureQuote: (ConnectionMediaItem, ConnectionSectionType, String) -> Void
    let onPresent: (UUID) -> Void
    let onClose: () -> Void

    /// Stage machinery for the presented atom-backed item. Recreated per item
    /// (`.task(id:)`), torn down on page change/close so no player outlives
    /// its moment on stage.
    @State private var stageModel: SwipeStudyModel?
    @State private var assetPlayer: AVPlayer?
    @State private var captionDraft: String = ""
    @FocusState private var captionFocused: Bool
    @State private var isTranscriptOpen = false
    @State private var capturedParagraphs: Set<String> = []

    private var presentedIndex: Int? {
        media.firstIndex { $0.id == presentedID }
    }

    private var presentedItem: ConnectionMediaItem? {
        media.first { $0.id == presentedID }
    }

    private var presentedAtom: Atom? {
        presentedItem?.atomUUID.flatMap { atoms[$0] }
    }

    var body: some View {
        ZStack {
            scrim
            if let item = presentedItem {
                lightboxCard(item)
                    .padding(DS.space48)
            }
            pagingArrows
        }
        .task(id: presentedID) { mountStage() }
        .onDisappear { teardownStage() }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    private var scrim: some View {
        Color.black.opacity(0.55)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onClose() }
            .accessibilityHidden(true)
    }

    // MARK: - Card

    private func lightboxCard(_ item: ConnectionMediaItem) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            stage(item)
                .frame(maxWidth: 720, maxHeight: 560)
                .frame(maxWidth: .infinity, alignment: .center)
            captionField(item)
            sourceLine(item)
            if !transcriptParagraphs.isEmpty {
                transcriptDrawer(item)
            }
            actionRow(item)
        }
        .padding(DS.space20)
        .frame(maxWidth: 800)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .onTapGesture { /* absorb: card taps must not close */ }
    }

    // MARK: - Stage

    @ViewBuilder
    private func stage(_ item: ConnectionMediaItem) -> some View {
        if let atom = presentedAtom, let model = stageModel {
            // The full Study stage: reel player, carousel pager, YouTube,
            // metadata + processing lines — one implementation everywhere.
            SwipeStudyStagePane(model: model, atom: atom)
        } else if let path = item.assetPath, item.ownsVideoAsset {
            ownedVideoStage(path: path)
        } else if item.assetPath != nil || item.assetRemoteURL != nil {
            ownedImageStage(item)
        } else {
            missingStage
        }
    }

    @ViewBuilder
    private func ownedVideoStage(path: String) -> some View {
        if let player = assetPlayer {
            CosmoVideoPlayerView(player: player)
                .clipShape(.rect(cornerRadius: 14))
        } else {
            Rectangle()
                .fill(DS.glassSectionFill)
                .overlay(ProgressView().controlSize(.small))
                .clipShape(.rect(cornerRadius: 14))
        }
    }

    private func ownedImageStage(_ item: ConnectionMediaItem) -> some View {
        ConceptOwnedImageStage(item: item)
    }

    private var missingStage: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(DS.glassSectionFill)
            .frame(height: 240)
            .overlay(
                VStack(spacing: DS.space8) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(DS.title1)
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                    Text("Source unavailable")
                        .font(DS.subheadline)
                        .foregroundStyle(DS.textSecondary)
                }
            )
    }

    // MARK: - Caption

    private func captionField(_ item: ConnectionMediaItem) -> some View {
        TextField("Add a caption…", text: $captionDraft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .lineLimit(1...3)
            .focused($captionFocused)
            .onSubmit { onCaptionCommit(item.id, captionDraft) }
            .onChange(of: captionFocused) { _, focused in
                if !focused { onCaptionCommit(item.id, captionDraft) }
            }
            .accessibilityLabel("Media caption")
    }

    // MARK: - Source line

    @ViewBuilder
    private func sourceLine(_ item: ConnectionMediaItem) -> some View {
        HStack(spacing: DS.space6) {
            if let atom = presentedAtom {
                if let title = atom.title, !title.isEmpty {
                    Text(title)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            } else if let title = item.assetTitle {
                Text(title)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            if let anchor = item.anchorSection {
                Text("·").foregroundStyle(DS.textMuted)
                Label(anchor.displayName, systemImage: anchor.icon)
                    .font(DS.footnote)
                    .foregroundStyle(anchor.accentColor)
            }
            if let moment = item.timestampSeconds, moment > 0 {
                Text("·").foregroundStyle(DS.textMuted)
                Label(Self.timestampLabel(moment), systemImage: "pin")
                    .font(DS.footnote.monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityLabel("Pinned moment \(Self.timestampLabel(moment))")
            }
            Spacer(minLength: 0)
            if let index = presentedIndex {
                Text("\(index + 1) of \(media.count)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .contentTransition(.numericText())
            }
        }
    }

    static func timestampLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Transcript drawer (pull-quote capture)

    /// Transcript paragraphs of the presented source, most useful for reels
    /// and YouTube videos. Slide-based transcripts join per slide.
    private var transcriptParagraphs: [String] {
        guard let atom = presentedAtom else { return [] }
        var text = atom.richContent?.formattedTranscript ?? atom.richContent?.transcript ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let slides = atom.swipeAnalysis?.transcriptSlides {
            text = slides.map(\.text).joined(separator: "\n\n")
        }
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
        return Array(paragraphs.prefix(80))
    }

    private func transcriptDrawer(_ item: ConnectionMediaItem) -> some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            Button {
                withAnimation(ProMotionSprings.gentle) { isTranscriptOpen.toggle() }
            } label: {
                HStack(spacing: DS.space6) {
                    Image(systemName: isTranscriptOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                    Text("Transcript")
                        .font(DS.footnote.weight(.medium))
                        .foregroundStyle(DS.textSecondary)
                    Text("hover a line to capture it into a section")
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .opacity(isTranscriptOpen ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isTranscriptOpen ? "Collapse transcript" : "Expand transcript")

            if isTranscriptOpen {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.space4) {
                        ForEach(Array(transcriptParagraphs.enumerated()), id: \.offset) { _, paragraph in
                            transcriptRow(item, paragraph: paragraph)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private func transcriptRow(_ item: ConnectionMediaItem, paragraph: String) -> some View {
        ConceptTranscriptCaptureRow(
            paragraph: paragraph,
            isCaptured: capturedParagraphs.contains(paragraph),
            onCapture: { section in
                onCaptureQuote(item, section, paragraph)
                withAnimation(ProMotionSprings.gentle) {
                    _ = capturedParagraphs.insert(paragraph)
                }
            }
        )
    }

    // MARK: - Actions

    private func actionRow(_ item: ConnectionMediaItem) -> some View {
        HStack(spacing: DS.space12) {
            if let atomUUID = item.atomUUID {
                Button {
                    onClose()
                    actions.onOpenMediaAsPane(atomUUID)
                } label: {
                    Label("Open as Pane", systemImage: "rectangle.split.2x1")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Open the source beside this concept (⌘⏎)")
            }
            if canPinMoment {
                Button {
                    if let model = stageModel {
                        onPinMoment(item.id, model.currentTimestamp)
                    }
                } label: {
                    Label("Pin Moment", systemImage: "pin")
                }
                .help("Remember this timestamp as the ref's start moment")
            }
            Button {
                actions.onToggleMediaCover(item.id)
            } label: {
                Label(item.isCover ? "Remove Cover" : "Set as Cover", systemImage: item.isCover ? "star.fill" : "star")
            }
            anchorMenu(item)
            Spacer(minLength: 0)
            Button(role: .destructive) {
                actions.onDetachMedia(item.id)
            } label: {
                Label("Detach", systemImage: "minus.circle")
            }
            .help("Remove from this concept (the source stays in your library)")
        }
        .buttonStyle(.plain)
        .font(DS.footnote.weight(.medium))
        .foregroundStyle(DS.textSecondary)
        .labelStyle(.titleAndIcon)
    }

    private var canPinMoment: Bool {
        guard presentedItem?.kind == .video else { return false }
        return stageModel?.isPlayerActive == true
    }

    private func anchorMenu(_ item: ConnectionMediaItem) -> some View {
        Menu {
            Button("Gallery only") { actions.onAnchorMedia(item.id, nil) }
            Divider()
            ForEach(ConnectionSectionType.allCases.filter { $0 != .conceptName }, id: \.self) { type in
                Button {
                    actions.onAnchorMedia(item.id, type)
                } label: {
                    if item.anchorSection == type {
                        Label(type.displayName, systemImage: "checkmark")
                    } else {
                        Text(type.displayName)
                    }
                }
            }
        } label: {
            Label(item.anchorSection?.displayName ?? "Section", systemImage: "square.grid.2x2")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Show this media on a section card")
    }

    // MARK: - Paging

    @ViewBuilder
    private var pagingArrows: some View {
        if media.count > 1, let index = presentedIndex {
            HStack {
                if index > 0 {
                    pagingArrow("chevron.left", label: "Previous media") {
                        onPresent(media[index - 1].id)
                    }
                }
                Spacer()
                if index < media.count - 1 {
                    pagingArrow("chevron.right", label: "Next media") {
                        onPresent(media[index + 1].id)
                    }
                }
            }
            .padding(.horizontal, DS.space16)
        }
    }

    private func pagingArrow(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DS.title3.weight(.semibold))
                .foregroundStyle(DS.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Stage lifecycle

    private func mountStage() {
        teardownStage()
        guard let item = presentedItem else { return }
        captionDraft = item.caption ?? ""

        if let atom = presentedAtom {
            let model = SwipeStudyModel(atom: atom, onClose: {})
            // A pinned moment starts YouTube playback there; the player reads
            // currentTimestamp when it activates.
            if let moment = item.timestampSeconds {
                model.currentTimestamp = moment
            }
            stageModel = model
        } else if let path = item.assetPath, item.ownsVideoAsset,
                  FileManager.default.fileExists(atPath: path) {
            let player = AVPlayer(url: URL(fileURLWithPath: path))
            if let moment = item.timestampSeconds, moment > 0 {
                player.seek(to: CMTime(seconds: moment, preferredTimescale: 600))
            }
            assetPlayer = player
        }
    }

    private func teardownStage() {
        stageModel?.igPlayer?.pause()
        stageModel = nil
        assetPlayer?.pause()
        assetPlayer = nil
    }
}

// MARK: - Transcript capture row

/// One transcript paragraph with a hover capture menu — the watch →
/// highlight → evidence loop. Captured rows wear a quiet check.
private struct ConceptTranscriptCaptureRow: View {
    let paragraph: String
    let isCaptured: Bool
    let onCapture: (ConnectionSectionType) -> Void

    @State private var isHovered = false

    /// Sections a pull-quote plausibly lands in, ordered by likelihood.
    private static let captureSections: [ConnectionSectionType] = [
        .evidence, .claims, .examples, .process, .beliefsObjections, .openQuestions
    ]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space6) {
            Text(paragraph)
                .font(DS.footnote)
                .foregroundStyle(isCaptured ? DS.textMuted : DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if isCaptured {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(DS.accent)
                    .accessibilityLabel("Captured")
            } else {
                Menu {
                    ForEach(Self.captureSections, id: \.self) { section in
                        Button {
                            onCapture(section)
                        } label: {
                            Label(section.displayName, systemImage: section.icon)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(DS.caption)
                        .foregroundStyle(DS.accent)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(isHovered ? 1 : 0)
                .help("Capture this line into a section")
                .accessibilityLabel("Capture this line into a section")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .background(isHovered ? DS.glassSectionFill : Color.clear, in: .rect(cornerRadius: 4))
    }
}

// MARK: - Owned image stage

/// Image hero for owned assets: resolves local-or-remote through
/// MediaAssetStore, renders fit.
private struct ConceptOwnedImageStage: View {
    let item: ConnectionMediaItem

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 14))
                    .accessibilityLabel(item.caption ?? item.assetTitle ?? "Image")
            } else if failed {
                RoundedRectangle(cornerRadius: 14)
                    .fill(DS.glassSectionFill)
                    .frame(height: 240)
                    .overlay(
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(DS.title1)
                            .foregroundStyle(DS.textMuted)
                            .accessibilityHidden(true)
                    )
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(DS.glassSectionFill)
                    .frame(height: 240)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: item.id) {
            image = await MediaAssetStore.resolveImage(item)
            failed = image == nil
        }
    }
}
