// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyPatternsSection.swift
// The PATTERNS rail section: recurring, idiosyncratic moves the PatternWeaver
// has noticed across the swipe library that THIS swipe belongs to. Each row
// names the move and shows the sibling swipes that share it — clicking a
// sibling navigates Study there. Until enough swipes share a move, the
// section teaches instead of hiding.
// July 2026

import SwiftUI

struct SwipeStudyPatternsSection: View {
    @Bindable var model: SwipeStudyModel
    let atom: Atom

    private var memberships: [SwipePattern] {
        SwipePatternStore.shared.patterns(containing: atom.uuid)
    }

    var body: some View {
        let patterns = memberships
        VStack(alignment: .leading, spacing: DS.space10) {
            SwipeStudyRailHeader(label: "PATTERNS", count: patterns.isEmpty ? nil : patterns.count)
            if patterns.isEmpty {
                teachingRow
            } else {
                VStack(alignment: .leading, spacing: DS.space8) {
                    ForEach(patterns) { pattern in
                        SwipeStudyPatternRow(pattern: pattern, currentUUID: atom.uuid) { entityId in
                            model.reloadWithEntity(entityId)
                        }
                    }
                }
            }
        }
    }

    /// Absence teaches — patterns appear once the weaver has enough evidence.
    private var teachingRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "circle.hexagongrid")
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Patterns surface once a few of your swipes share a move.")
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Pattern row

struct SwipeStudyPatternRow: View {
    let pattern: SwipePattern
    let currentUUID: String
    let onOpenSibling: (Int64) -> Void

    @State private var siblings: [PatternSibling] = []
    @State private var isExpanded = false
    @State private var isHovered = false

    struct PatternSibling: Identifiable {
        let id: Int64
        let uuid: String
        let title: String
        let thumbnailURL: URL?
        let evidence: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Button {
                withAnimation(ProMotionSprings.snappy) { isExpanded.toggle() }
            } label: {
                headerRow
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(pattern.name), \(pattern.members.count) swipes. \(pattern.definition)")

            if isExpanded {
                Text(pattern.definition)
                    .font(DS.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !siblings.isEmpty {
                    siblingStrip
                }
            }
        }
        .padding(DS.space10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered || isExpanded ? DS.glassSectionFill : DS.glassSectionFill.opacity(0.6))
        )
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .task(id: pattern.id) {
            await loadSiblings()
        }
    }

    private var headerRow: some View {
        HStack(spacing: DS.space8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.name)
                    .font(DS.callout.weight(.semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Text("\(pattern.level.displayName) · \(pattern.members.count) swipes")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(DS.textMuted)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var siblingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space6) {
                ForEach(siblings) { sibling in
                    siblingThumb(sibling)
                }
            }
        }
    }

    private func siblingThumb(_ sibling: PatternSibling) -> some View {
        Button {
            onOpenSibling(sibling.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Group {
                    if let url = sibling.thumbnailURL {
                        CachedAsyncImage(url: url, stableKey: "pattern-sib-\(sibling.uuid)") { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
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
                .frame(width: 64, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DS.glassBorder, lineWidth: 0.5)
                )

                Text(sibling.title)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
                    .frame(width: 64, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sibling.evidence.isEmpty ? sibling.title : sibling.evidence)
        .accessibilityLabel("Open \(sibling.title)")
    }

    private func loadSiblings() async {
        var loaded: [PatternSibling] = []
        for member in pattern.members where member.swipeUUID != currentUUID {
            guard loaded.count < 6 else { break }
            guard let atom = try? await AtomRepository.shared.fetch(uuid: member.swipeUUID),
                  let id = atom.id else { continue }
            loaded.append(PatternSibling(
                id: id,
                uuid: atom.uuid,
                title: atom.title ?? "Untitled",
                thumbnailURL: (atom.thumbnailUrl ?? atom.richContent?.thumbnailUrl).flatMap(URL.init(string:)),
                evidence: member.evidence
            ))
        }
        siblings = loaded
    }
}
