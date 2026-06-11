// CosmoOS/UI/FocusMode/Content/SpokesCompilerView.swift
// The spokes staging board — pillar on the left, format cards on the right.
// Every ready card shows a true-to-format preview (tweet cells, mini slides,
// subject + lede), never a wall of raw text.

import SwiftUI

struct SpokesCompilerView: View {
    let pillar: Atom
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = SpokesCompilerEngine()
    @State private var selectedFormats: Set<SpokesCompilerEngine.SpokeFormat> = [.newsletter, .thread, .reel, .carousel]

    var body: some View {
        HStack(spacing: 0) {
            pillarRail
            divider
            board
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear { engine.prepare(pillar: pillar) }
    }

    // MARK: Pillar rail

    private var pillarRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(DS.caption)
                    .foregroundStyle(DS.entityContent)
                Text("Pillar")
                    .font(DS.caption)
                    .tracking(0.3)
                    .foregroundStyle(DS.textMuted)
            }

            Text(pillar.title ?? "Untitled")
                .font(DS.title2)
                .foregroundStyle(DS.text)
                .lineLimit(3)

            ScrollView(.vertical) {
                Text(pillar.body ?? "")
                    .font(DS.body)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
        .frame(width: 300)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(width: 1)
    }

    // MARK: Board

    private var board: some View {
        VStack(spacing: 0) {
            boardHeader
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(Array(engine.spokes.enumerated()), id: \.element.id) { index, spoke in
                        SpokeCard(
                            spoke: spoke,
                            isSelected: selectedFormats.contains(spoke.format),
                            appearIndex: index,
                            onToggle: { toggle(spoke.format) },
                            onAccept: { Task { _ = await engine.accept(spoke.id) } },
                            onRegenerate: { Task { await engine.regenerate(spoke.id) } }
                        )
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var boardHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Compile Spokes")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
                Text("One pillar in — a platform package out. Accept what's good; nothing lands until you do.")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer(minLength: 16)

            compileButton
            closeButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var compileButton: some View {
        Button {
            Task { await engine.compile(formats: selectedFormats) }
        } label: {
            HStack(spacing: 6) {
                if engine.isCompiling {
                    Image(systemName: "circle.dotted")
                        .font(DS.caption)
                } else {
                    Image(systemName: "sparkles")
                        .font(DS.caption)
                }
                Text(engine.isCompiling ? "Drafting…" : "Compile \(selectedFormats.count)")
                    .font(DS.callout.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(DS.accent))
            .opacity(engine.isCompiling || selectedFormats.isEmpty ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(engine.isCompiling || selectedFormats.isEmpty)
        .help("Draft the selected formats (⏎)")
        .keyboardShortcut(.return, modifiers: [.command])
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(DS.glassCardFill))
                .overlay(Circle().strokeBorder(DS.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Close (esc)")
        .accessibilityLabel("Close spokes compiler")
    }

    private func toggle(_ format: SpokesCompilerEngine.SpokeFormat) {
        withAnimation(ProMotionSprings.snappy) {
            if selectedFormats.contains(format) {
                selectedFormats.remove(format)
            } else {
                selectedFormats.insert(format)
            }
        }
    }
}

// MARK: - Spoke Card

private struct SpokeCard: View {
    let spoke: SpokesCompilerEngine.Spoke
    let isSelected: Bool
    let appearIndex: Int
    let onToggle: () -> Void
    let onAccept: () -> Void
    let onRegenerate: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader
            cardBody
            if spoke.state == .ready {
                cardFooter
            }
        }
        .padding(14)
        .glassCard(isHovered: isHovered, cornerRadius: 14)
        .opacity(hasAppeared ? (isSelected || spoke.state != .queued ? 1 : 0.55) : 0)
        .scaleEffect(hasAppeared ? 1 : 0.96)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
        }
        .onAppear {
            guard !reduceMotion else { hasAppeared = true; return }
            guard !hasAppeared else { return }
            withAnimation(ProMotionSprings.cascade(index: min(appearIndex, 8))) {
                hasAppeared = true
            }
        }
    }

    // MARK: Header

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: spoke.format.icon)
                .font(DS.subheadline)
                .foregroundStyle(DS.entityContent)
            Text(spoke.format.displayName)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Spacer(minLength: 8)

            switch spoke.state {
            case .queued:
                Toggle("", isOn: .init(get: { isSelected }, set: { _ in onToggle() }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(isSelected ? "Included in compile" : "Excluded from compile")
            case .drafting:
                Text("Drafting…")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            case .ready:
                EmptyView()
            case .accepted:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.caption)
                    Text("In pipeline")
                        .font(DS.caption)
                }
                .foregroundStyle(DS.accent)
            case .failed:
                Button("Retry", action: onRegenerate)
                    .buttonStyle(.plain)
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
            }
        }
    }

    // MARK: Body

    @ViewBuilder
    private var cardBody: some View {
        switch spoke.state {
        case .queued:
            Text(queuedHint)
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        case .drafting:
            skeleton
        case .ready, .accepted:
            SpokePreview(format: spoke.format, draft: spoke.draft)
        case .failed(let message):
            Text(message)
                .font(DS.caption)
                .foregroundStyle(DS.red)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        }
    }

    private var queuedHint: String {
        switch spoke.format {
        case .newsletter: return "Subject, lede, and 3–5 tight sections from the pillar."
        case .thread: return "6–12 tweets, one idea each, hook first."
        case .reel: return "30–45s script — one sentence per slide."
        case .carousel: return "6–8 slides, ~4 sentences each, screenshot-worthy."
        case .post: return "One scannable post with the hook above the fold."
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DS.glassSectionFill)
                    .frame(height: 10)
                    .frame(maxWidth: index == 3 ? 140 : .infinity)
            }
        }
        .frame(minHeight: 64)
    }

    // MARK: Footer

    private var cardFooter: some View {
        HStack(spacing: 8) {
            Text(footerStats)
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textMuted)

            Spacer(minLength: 8)

            Button("Regenerate", action: onRegenerate)
                .buttonStyle(.plain)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
                .help("Draft this format again")

            Button(action: onAccept) {
                Text("Accept")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(DS.accent))
            }
            .buttonStyle(.plain)
            .help("Create a linked content draft in the pipeline")
        }
    }

    private var footerStats: String {
        switch spoke.format {
        case .thread:
            let tweets = SpokePreview.segments(draft: spoke.draft, separator: "\n\n")
            return "\(tweets.count) tweets"
        case .reel, .carousel:
            let slides = SpokePreview.segments(draft: spoke.draft, separator: "---")
            return "\(slides.count) slides"
        case .newsletter, .post:
            let words = spoke.draft.split(whereSeparator: \.isWhitespace).count
            return "\(words) words"
        }
    }
}

// MARK: - True-to-format previews

struct SpokePreview: View {
    let format: SpokesCompilerEngine.SpokeFormat
    let draft: String

    static func segments(draft: String, separator: String) -> [String] {
        draft
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 190)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        switch format {
        case .thread:
            threadPreview
        case .reel, .carousel:
            slidesPreview
        case .newsletter:
            newsletterPreview
        case .post:
            postPreview
        }
    }

    // Thread → stacked tweet cells
    private var threadPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.segments(draft: draft, separator: "\n\n").enumerated()), id: \.offset) { _, tweet in
                Text(tweet)
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                    .lineSpacing(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DS.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DS.borderSubtle, lineWidth: 0.5)
                    )
            }
        }
    }

    // Reel / carousel → numbered mini slides
    private var slidesPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.segments(draft: draft, separator: "---").enumerated()), id: \.offset) { index, slide in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(DS.caption2.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 16, alignment: .trailing)
                        .padding(.top, 8)

                    Text(slide)
                        .font(DS.caption)
                        .foregroundStyle(DS.text)
                        .lineSpacing(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DS.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(DS.borderSubtle, lineWidth: 0.5)
                        )
                }
            }
        }
    }

    // Newsletter → subject line emphasized, then body
    private var newsletterPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let subject = draft.components(separatedBy: "\n").first {
                Text(subject.replacingOccurrences(of: "Subject:", with: "").trimmingCharacters(in: .whitespaces))
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
            }
            Text(bodyAfterSubject)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineSpacing(3)
        }
    }

    private var bodyAfterSubject: String {
        let lines = draft.components(separatedBy: "\n")
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var postPreview: some View {
        Text(draft)
            .font(DS.caption)
            .foregroundStyle(DS.text)
            .lineSpacing(3)
    }
}
