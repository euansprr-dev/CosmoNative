// CosmoOS/UI/FocusMode/Connection/TheWellView.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// The left zone: 280pt of vellum holding sources as manuscript cards with their
// whispers grouped beneath. Hovering a source reports a set of "endpoint ids"
// through the ley-line preference key so TheForgeView can draw bezier traces to
// every station that source has contributed to. The well is where research
// enters the room; the whispers live beside the voice that spoke them.

import SwiftUI

struct TheWellView: View {

    // MARK: - Inputs

    let sources: [Atom]
    /// Whispers grouped by `sourceAtomUUID`. Sources without whispers still render.
    let whispersBySource: [String: [GhostSuggestion]]
    let isLoadingSources: Bool

    let onAddSource: () -> Void
    let onSourceTap: (String) -> Void
    let onRefreshWhispers: (String) -> Void
    let onAcceptWhisper: (GhostSuggestion) -> Void
    let onDismissWhisper: (UUID) -> Void
    /// Emits the hovered source UUID (or nil). TheForgeView uses this to fade
    /// in ley lines from the source to its contributed stations.
    let onHoverSource: (String?) -> Void

    /// Per-source contribution counts — used for the 4-dot manuscript row.
    let contributionsBySource: [String: Set<ConnectionSectionType>]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            addSourceFooter
        }
        .frame(width: 280)
        .background(DS.vellum)
        .overlay(alignment: .trailing) { verticalHairline }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.system(size: 10))
                .foregroundStyle(DS.gilt.opacity(0.7))
                .accessibilityHidden(true)
            Text("THE WELL")
                .font(DS.smallCaps)
                .tracking(1.8)
                .foregroundStyle(DS.giltMuted)
            Spacer()
            if !sources.isEmpty {
                Text("\(sources.count)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoadingSources {
            loadingView
        } else if sources.isEmpty {
            emptyState
        } else {
            sourceList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 40)
            ProgressView().scaleEffect(0.6)
            Text("Finding sources…")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DS.inkFaded)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 32)
            Image(systemName: "books.vertical")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.inkFaded)
                .accessibilityHidden(true)
            Text("Drag research, ideas, or swipes here.")
                .font(.system(size: 12, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkFaded)
                .multilineTextAlignment(.center)
            Text("The whispers come from what you bring.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DS.inkFaded)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private var sourceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(sources, id: \.uuid) { source in
                    SourceManuscriptCard(
                        source: source,
                        whispers: whispersBySource[source.uuid] ?? [],
                        contributedStations: contributionsBySource[source.uuid] ?? [],
                        onTap: { onSourceTap(source.uuid) },
                        onRefreshWhispers: { onRefreshWhispers(source.uuid) },
                        onAcceptWhisper: onAcceptWhisper,
                        onDismissWhisper: onDismissWhisper,
                        onHover: { hovering in
                            onHoverSource(hovering ? source.uuid : nil)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Footer

    private var addSourceFooter: some View {
        Button(action: onAddSource) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                Text("ADD SOURCE")
                    .font(DS.smallCaps)
                    .tracking(1.4)
            }
            .foregroundStyle(DS.giltMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.sepiaSubtle).frame(height: 0.5)
        }
    }

    private var verticalHairline: some View {
        Rectangle().fill(DS.sepiaSubtle).frame(width: 0.5)
    }
}

// MARK: - Source Manuscript Card

private struct SourceManuscriptCard: View {

    let source: Atom
    let whispers: [GhostSuggestion]
    let contributedStations: Set<ConnectionSectionType>
    let onTap: () -> Void
    let onRefreshWhispers: () -> Void
    let onAcceptWhisper: (GhostSuggestion) -> Void
    let onDismissWhisper: (UUID) -> Void
    let onHover: (Bool) -> Void

    @State private var isHovering: Bool = false

    private var sourceID: String { "well-source-\(source.uuid)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
            contributionDots
            if !whispers.isEmpty {
                whispersColumn
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(DS.vellumDeep.opacity(isHovering ? 0.85 : 0.55), in: .rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.sepiaBorder.opacity(isHovering ? 0.9 : 0.5), lineWidth: 0.5)
        )
        .shadow(color: DS.inkWash.opacity(isHovering ? 0.08 : 0), radius: 6, y: 2)
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
        }
        .reportLeyEndpoint(sourceID, in: "forge-space")
        .contentShape(Rectangle())
    }

    private var titleRow: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: glyph(for: source.type))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.gilt.opacity(0.7))
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(source.title ?? "Untitled Source")
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundStyle(DS.inkWash)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if isHovering {
                    refreshButton
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var refreshButton: some View {
        Button(action: onRefreshWhispers) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9))
                .foregroundStyle(DS.giltMuted)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh whispers for this source")
    }

    private var contributionDots: some View {
        HStack(spacing: 4) {
            ForEach(contributionPreview, id: \.self) { type in
                Circle()
                    .fill(type.accentColor.opacity(0.85))
                    .frame(width: 4, height: 4)
            }
            let remaining = max(0, contributedStations.count - contributionPreview.count)
            if remaining > 0 {
                Text("+\(remaining)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.inkFaded)
            }
            Spacer(minLength: 4)
            if !whispers.isEmpty {
                Text("\(whispers.count) whisper\(whispers.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(DS.inkFaded)
                    .italic()
            }
        }
        .frame(height: 10)
    }

    /// Stable ordering so the dot row doesn't jump.
    private var contributionPreview: [ConnectionSectionType] {
        ConnectionSectionType.allCases
            .filter { contributedStations.contains($0) }
            .prefix(4)
            .map { $0 }
    }

    private var whispersColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(whispers) { whisper in
                WellWhisperRow(
                    whisper: whisper,
                    onAccept: { onAcceptWhisper(whisper) },
                    onDismiss: { onDismissWhisper(whisper.id) }
                )
            }
        }
    }

    private func glyph(for type: AtomType) -> String {
        switch type {
        case .research: return source.isSwipeFileAtom ? "bookmark" : "doc.text"
        case .idea: return "lightbulb"
        case .content: return "doc.richtext"
        case .connection: return "link"
        case .project: return "folder"
        case .clientProfile: return "person.crop.circle"
        case .note: return "note.text"
        case .task: return "checkmark.circle"
        default: return "circle"
        }
    }
}

// MARK: - Well Whisper Row

private struct WellWhisperRow: View {

    let whisper: GhostSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            destinationLabel
            Text(whisper.content)
                .font(.system(size: 11, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(DS.inkWash.opacity(0.85))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            actionRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DS.vellum, in: .rect(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(whisper.targetSectionType.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
        )
        .onHover { isHovering = $0 }
    }

    private var destinationLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(whisper.targetSectionType.accentColor.opacity(0.8))
                .frame(width: 4, height: 4)
            Text(whisper.targetSectionType.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(1.2)
                .foregroundStyle(whisper.targetSectionType.accentColor.opacity(0.85))
            Spacer(minLength: 4)
            confidenceArc
        }
    }

    /// A thin gilt arc visualizing confidence (0-1) — 12pt wide, 3pt tall.
    private var confidenceArc: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 0.5
            let rect = CGRect(
                x: inset, y: inset,
                width: size.width - inset * 2, height: size.height * 2 - inset * 2
            )
            let sweep = Double(whisper.confidence) * .pi
            var path = Path()
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.maxY),
                radius: min(rect.width, rect.height) / 2,
                startAngle: .radians(.pi),
                endAngle: .radians(.pi + sweep),
                clockwise: false
            )
            ctx.stroke(path, with: .color(DS.gilt.opacity(0.85)), lineWidth: 1)
        }
        .frame(width: 14, height: 4)
        .accessibilityLabel("Confidence \(whisper.confidencePercent) percent")
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: onAccept) {
                HStack(spacing: 3) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                    Text("CRYSTALLIZE")
                        .font(DS.smallCaps)
                        .tracking(1.0)
                }
                .foregroundStyle(whisper.targetSectionType.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().stroke(whisper.targetSectionType.accentColor.opacity(0.55), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            if isHovering {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DS.inkFaded)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss whisper")
            }
            Spacer()
        }
    }
}
