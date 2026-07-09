// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyManuscript.swift
// The reading column: one serif hero title, one quiet metadata line, then the
// transcript — editable slide cards for Instagram, selectable prose for
// YouTube/plain sources. The single serif moment on the page is the title.
// July 2026

import SwiftUI

struct SwipeStudyManuscript: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            SwipeStudyHeroBlock(model: model, atom: atom)
            SwipeStudyTranscriptBlock(model: model, atom: atom)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Transcript chooser

/// The transcript in whichever shape the source demands — slide cards for
/// Instagram, selectable prose otherwise. Adaptive tiers place this directly.
struct SwipeStudyTranscriptBlock: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom

    var body: some View {
        if model.isInstagramSwipe(atom) {
            SwipeStudySlideTranscript(model: model, atom: atom)
        } else {
            SwipeStudyProseTranscript(model: model, atom: atom)
        }
    }
}

// MARK: - Hero block (title + meta + engagement)

struct SwipeStudyHeroBlock: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom
    /// Medium tier renders the hero beside the media at a smaller measure.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text(model.heroTitle)
                .font(compact ? DS.spaceTitleSerif : DS.displaySerif)
                .foregroundStyle(DS.text)
                .lineSpacing(compact ? 2 : 3)
                .lineLimit(compact ? 4 : 3)
                .textSelection(.enabled)

            metaLine
            engagementLine
        }
    }

    private var metaLine: some View {
        HStack(spacing: DS.space6) {
            ForEach(Array(metaParts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text("·").foregroundStyle(DS.textMuted)
                }
                if part.isCreatorLink {
                    Button(part.text) { model.openLinkedCreator() }
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.textSecondary)
                        .pointerStyle(.link)
                        .help("Open creator profile")
                } else {
                    Text(part.text)
                        .foregroundStyle(DS.textMuted)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .font(DS.subheadline)
    }

    private struct MetaPart {
        let text: String
        var isCreatorLink = false
    }

    private var metaParts: [MetaPart] {
        var parts: [MetaPart] = []
        if model.analysis?.creatorUUID?.isEmpty == false {
            parts.append(MetaPart(text: "Creator", isCreatorLink: true))
        }
        if let format = model.analysis?.swipeContentFormat {
            parts.append(MetaPart(text: format.displayName))
        } else {
            parts.append(MetaPart(text: model.sourceDescriptor(for: atom)))
        }
        if let score = model.analysis?.effectiveHookScore, score > 0 {
            parts.append(MetaPart(text: String(format: "Hook %.1f", score)))
        }
        if let date = ISO8601.date(from: atom.createdAt) {
            parts.append(MetaPart(text: "Saved \(date.formatted(.dateTime.day().month(.abbreviated)))"))
        }
        return parts
    }

    /// Quiet engagement stats — only when the worker captured them.
    @ViewBuilder
    private var engagementLine: some View {
        if let analysis = model.analysis,
           analysis.viewsCount != nil || analysis.likesCount != nil || analysis.commentsCount != nil {
            HStack(spacing: DS.space12) {
                if let views = analysis.viewsCount {
                    statPair(icon: "play.fill", value: views)
                }
                if let likes = analysis.likesCount {
                    statPair(icon: "heart.fill", value: likes)
                }
                if let comments = analysis.commentsCount {
                    statPair(icon: "bubble.right.fill", value: comments)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Engagement stats")
        }
    }

    private func statPair(icon: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text(SwipeStudyModel.compactCount(value))
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textSecondary)
        }
    }
}

// MARK: - Compact header (small panes)

/// The small-pane header: thumbnail beside the title, one meta line, and the
/// insight as a short reading moment — the transcript below stays the hero of
/// a narrow surface without a full-width poster shoving it down.
struct SwipeStudyCompactHeader: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(alignment: .top, spacing: DS.space12) {
                thumbnail
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text(model.heroTitle)
                        .font(DS.spaceTitleSerif)
                        .foregroundStyle(DS.text)
                        .lineSpacing(2)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    compactMetaLine
                }
                Spacer(minLength: 0)
            }
            insightSnippet
        }
    }

    private var thumbnail: some View {
        Group {
            if let url = model.igMediaData?.thumbnailURL
                ?? model.extractThumbnailUrl(from: atom).flatMap(URL.init(string:)) {
                CachedAsyncImage(url: url, stableKey: "swipe-compact-\(atom.uuid)") { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Rectangle().fill(DS.glassSectionFill)
                    }
                }
            } else {
                Rectangle()
                    .fill(DS.glassSectionFill)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                            .accessibilityHidden(true)
                    )
            }
        }
        .frame(width: 76, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DS.glassBorder, lineWidth: 0.5)
        )
    }

    private var compactMetaLine: some View {
        HStack(spacing: DS.space6) {
            Text(model.analysis?.swipeContentFormat?.displayName ?? model.sourceDescriptor(for: atom))
            if let score = model.analysis?.effectiveHookScore, score > 0 {
                Text("·")
                Text(String(format: "Hook %.1f", score)).monospacedDigit()
            }
        }
        .font(DS.caption)
        .foregroundStyle(DS.textMuted)
    }

    @ViewBuilder
    private var insightSnippet: some View {
        if let insight = model.analysis?.keyInsight, !insight.isEmpty {
            Text(insight)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(3)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Slide transcript (Instagram)

struct SwipeStudySlideTranscript: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            header

            if model.isAutoTranscribing {
                autoTranscriptionProgressView
            }
            warningBanner

            if model.showRawTranscript {
                ForEach(model.displayedTranscriptSlides) { slide in
                    SwipeStudyRawSlideCard(slide: slide)
                }
                Text("Raw capture is read-only. Switch to Cleaned to edit.")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            } else {
                ForEach(model.transcriptSlides) { slide in
                    SwipeStudySlideCard(model: model, slide: slide)
                        .id(SwipeStudyScrollTarget.slide(slide.slideNumber))
                }
                addSlideRow
            }

            captionBlock
        }
        .transcriptScrollAnchor()
    }

    private var header: some View {
        HStack(spacing: DS.space10) {
            SwipeSectionHeader(label: "TRANSCRIPT", count: model.displayedTranscriptSlides.count)
            transcriptModeToggle
        }
    }

    private var transcriptModeToggle: some View {
        HStack(spacing: 2) {
            modePill("Cleaned", selected: !model.showRawTranscript) {
                model.showRawTranscript = false
            }
            modePill("Raw", selected: model.showRawTranscript) {
                model.showRawTranscript = true
            }
        }
        .padding(2)
        .background(DS.glassSectionFill, in: Capsule())
    }

    private func modePill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? DS.text : DS.textMuted)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(selected ? DS.accentSoft : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(selected ? DS.accent.opacity(0.25) : .clear, lineWidth: 0.5)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(ProMotionSprings.snappy, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var addSlideRow: some View {
        Button {
            model.appendSlide()
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: "plus")
                    .font(DS.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text("Add slide")
                    .font(DS.callout)
            }
            .foregroundStyle(DS.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.space10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.glassBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Add a slide (⌘⏎ inside a slide adds one below it)")
        .accessibilityLabel("Add slide")
    }

    @ViewBuilder
    private var autoTranscriptionProgressView: some View {
        HStack(spacing: DS.space8) {
            ProgressView().controlSize(.small)
            Text(model.autoTranscriptionProgress)
                .font(DS.footnote)
                .foregroundStyle(DS.textSecondary)
            Spacer()
        }
        .padding(DS.space10)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var warningBanner: some View {
        if model.shouldShowTranscriptionWarning {
            HStack(spacing: DS.space8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(DS.footnote)
                    .foregroundStyle(DS.orange)
                    .accessibilityHidden(true)
                Text(model.transcriptionWarningText)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(DS.space10)
            .background(DS.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.orange.opacity(0.18), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private var captionBlock: some View {
        if let caption = model.igMediaData?.caption ?? atom.richContent?.instagramData?.caption,
           !caption.isEmpty {
            VStack(alignment: .leading, spacing: DS.space10) {
                SwipeStudyRailHeader(label: "CAPTION")
                Text(caption)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(DS.space12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SwipeTranscriptCardPalette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(SwipeTranscriptCardPalette.border, lineWidth: 0.5)
                    )
            }
            .padding(.top, DS.space8)
        }
    }
}

// MARK: - One editable slide card

struct SwipeStudySlideCard: View {
    @Bindable var model: SwipeStudyModel
    let slide: TranscriptSlide

    @State private var isHovered = false

    private var index: Int { model.indexForSlide(withID: slide.id) ?? 0 }

    var body: some View {
        let slideComments = model.commentsForSlide(index)
        let composerOpen = model.activeCommentSlideIndex == index

        VStack(alignment: .leading, spacing: DS.space8) {
            cardHeader(commentCount: slideComments.count, composerOpen: composerOpen)

            SlideTextEditor(
                slideID: slide.id,
                text: model.bindingForSlideText(slide.id),
                focusRequestID: $model.slideFocusRequestID,
                onNewSlide: { model.insertSlide(after: slide.id) }
            )

            if composerOpen {
                commentComposer
            }
            if !slideComments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(slideComments) { comment in
                        commentRow(comment)
                    }
                }
            }
        }
        .padding(DS.space12)
        .background(SwipeTranscriptCardPalette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    composerOpen ? DS.accent.opacity(0.3) : SwipeTranscriptCardPalette.border,
                    lineWidth: 0.5
                )
        )
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    private func cardHeader(commentCount: Int, composerOpen: Bool) -> some View {
        HStack(spacing: DS.space8) {
            Text(String(format: "%02d", index + 1))
                .font(DS.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .help(provenanceHelp)

            Spacer(minLength: 0)

            if slide.text.count > 400 {
                Text("\(slide.text.count)/\(TranscriptSlide.characterLimit)")
                    .font(DS.caption2.monospacedDigit())
                    .foregroundStyle(slide.text.count > TranscriptSlide.characterLimit ? DS.red : DS.textMuted)
            }

            Button {
                model.toggleCommentComposer(forSlide: index)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: commentCount > 0 ? "bubble.left.fill" : "bubble.left")
                        .font(DS.caption)
                        .accessibilityHidden(true)
                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(DS.caption2.monospacedDigit())
                    }
                }
                .foregroundStyle(composerOpen || commentCount > 0 ? DS.accent : DS.textMuted)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || composerOpen || commentCount > 0 ? 1 : 0)
            .help("Comment on this slide")
            .accessibilityLabel("Comment on slide \(index + 1)")

            if model.transcriptSlides.count > 1 {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        model.removeSlide(withID: slide.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.caption2.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .help("Delete slide")
                .accessibilityLabel("Delete slide \(index + 1)")
            }
        }
    }

    private var provenanceHelp: String {
        switch slide.source {
        case .manual: return "Slide \(index + 1) — typed by you"
        case .visionOCR: return "Slide \(index + 1) — on-screen text (OCR)"
        case .speechAudio: return "Slide \(index + 1) — spoken audio"
        case .merged: return "Slide \(index + 1) — merged OCR + speech"
        case .aiCleaned: return "Slide \(index + 1) — AI-cleaned"
        case .geminiVision: return "Slide \(index + 1) — Gemini vision OCR"
        case nil: return "Slide \(index + 1)"
        }
    }

    private var commentComposer: some View {
        HStack(spacing: DS.space6) {
            TextField("Add a comment…", text: $model.newCommentText)
                .textFieldStyle(.plain)
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
                .onSubmit { model.addComment(toSlide: index) }

            Button {
                model.addComment(toSlide: index)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(DS.title3)
                    .foregroundStyle(
                        model.newCommentText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? DS.textMuted : DS.accent
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Save comment")
        }
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space6)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func commentRow(_ comment: TranscriptComment) -> some View {
        HStack(alignment: .top, spacing: DS.space6) {
            Rectangle()
                .fill(DS.accent.opacity(0.35))
                .frame(width: 2)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(comment.text)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.formatCommentDate(comment.createdAt))
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    model.deleteComment(comment)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(minWidth: 18, minHeight: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete comment")
            .accessibilityLabel("Delete comment")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, DS.space6)
    }
}

// MARK: - Raw slide card (read-only)

struct SwipeStudyRawSlideCard: View {
    let slide: TranscriptSlide

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            HStack {
                Text(String(format: "%02d", slide.slideNumber))
                    .font(DS.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DS.textMuted)
                Spacer()
                if let timestamp = slide.timestamp {
                    Text(Self.formatTime(timestamp))
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                }
            }
            Text(slide.text.isEmpty ? "No text captured for this slide." : slide.text)
                .font(DS.callout)
                .foregroundStyle(slide.text.isEmpty ? SwipeTranscriptCardPalette.mutedText : SwipeTranscriptCardPalette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.space12)
        .background(SwipeTranscriptCardPalette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SwipeTranscriptCardPalette.border, lineWidth: 0.5)
        )
    }

    static func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Prose transcript (YouTube / plain sources)

struct SwipeStudyProseTranscript: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(spacing: DS.space10) {
                SwipeSectionHeader(label: "TRANSCRIPT", count: model.transcriptText.isEmpty ? 0 : 1)
                if model.isFetchingTranscript {
                    ProgressView().controlSize(.small)
                }
            }

            if !model.transcriptText.isEmpty {
                Text(model.transcriptText)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.editTranscriptText = model.transcriptText
                    model.showEditTranscript = true
                } label: {
                    Label("Edit transcript", systemImage: "pencil")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Correct auto-transcription errors")
            } else if model.isFetchingTranscript {
                VStack(alignment: .leading, spacing: DS.space10) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DS.glassSectionFill)
                            .frame(width: i == 4 ? 220 : nil, height: 13)
                    }
                }
                .padding(.vertical, DS.space4)
            } else {
                emptyTranscriptRow
            }
        }
        .transcriptScrollAnchor()
    }

    /// Absence teaches the fix — the container-grammar teaching row.
    private var emptyTranscriptRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "text.quote")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
            Text(model.transcriptFetchFailed
                 ? "Transcript fetch failed — retry from the menu, or add it by hand."
                 : "No transcript yet. Fetch or add text to unlock the analysis.")
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
            if model.transcriptFetchFailed {
                Button("Retry") { model.retryTranscriptFetch() }
                    .buttonStyle(.plain)
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Scroll anchor for structure-beat taps

extension View {
    /// Marks the transcript block so the insight rail's structure beats can
    /// scroll to it.
    func transcriptScrollAnchor() -> some View {
        self.id(SwipeStudyScrollTarget.transcript)
    }
}

enum SwipeStudyScrollTarget: Hashable {
    case transcript
    case slide(Int)   // 1-based slide number
}
