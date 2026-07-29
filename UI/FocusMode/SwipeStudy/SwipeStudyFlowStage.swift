// CosmoOS/UI/FocusMode/SwipeStudy/SwipeStudyFlowStage.swift
// The flow stage: a funnel as an ordered filmstrip of its member swipes.
//
// A flow's content IS its members, so the stage shows them rather than any
// artwork of its own. Clicking a step opens that swipe with the flow as the
// browsing session, which means ⌘[ / ⌘] then walk the funnel in order — the
// study bench's existing prev/next becomes funnel navigation for free.

import SwiftUI

struct SwipeStudyFlowStage: View {
    let units: [SwipeArtifactUnit]
    /// The flow itself, so opening a member can seed the browsing session.
    let flowUUID: String

    @State private var members: [String: Atom] = [:]
    @State private var hoveredUUID: String?

    private var orderedUnits: [SwipeArtifactUnit] {
        units.sorted { $0.index < $1.index }
    }

    var body: some View {
        Group {
            if orderedUnits.isEmpty {
                emptyState
            } else {
                filmstrip
            }
        }
        .task(id: orderedUnits.compactMap(\.memberSwipeUUID).joined()) {
            await loadMembers()
        }
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: DS.space12) {
                ForEach(orderedUnits) { unit in
                    stepTile(unit)
                }
            }
            .padding(.vertical, DS.space4)
        }
        .scrollIndicators(.never)
        // Card shadows and hover lift need room, or they clip at the edge.
        .contentMargins(.horizontal, DS.space8)
        .padding(.horizontal, -DS.space8)
    }

    private func stepTile(_ unit: SwipeArtifactUnit) -> some View {
        let member = unit.memberSwipeUUID.flatMap { members[$0] }
        let isHovered = hoveredUUID == unit.memberSwipeUUID

        return VStack(alignment: .leading, spacing: DS.space6) {
            ZStack {
                Rectangle().fill(DS.glassSectionFill)
                if let thumbnail = member?.researchMetadata?.thumbnailUrl.flatMap(URL.init(string:)) {
                    CachedAsyncImage(url: thumbnail, stableKey: unit.memberSwipeUUID) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .empty, .failure: Rectangle().fill(DS.glassSectionFill)
                        }
                    }
                } else {
                    Image(systemName: (member?.swipeKind ?? .post).iconName)
                        .font(DS.title3)
                        .foregroundStyle(DS.textMuted)
                }
            }
            .frame(width: 132, height: 165)
            .clipShape(.rect(cornerRadius: DS.radiusMedium, style: .continuous))
            .overlay(alignment: .topLeading) { stepNumber(unit.index + 1) }
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
                    .strokeBorder(isHovered ? DS.accent.opacity(0.5) : DS.glassBorder, lineWidth: isHovered ? 1 : 0.5)
            )

            if let role = unit.role {
                Text(role.displayName)
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            Text(unit.headline?.trimmed.isEmpty == false ? unit.headline! : (member?.title ?? "Step"))
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .lineLimit(2)
                .frame(width: 132, alignment: .leading)
        }
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { hovering in
            hoveredUUID = hovering ? unit.memberSwipeUUID : nil
        }
        .onTapGesture { open(unit) }
        .help(unit.mechanic ?? "Open this step")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(unit.index + 1): \(member?.title ?? "swipe")")
        .accessibilityAddTraits(.isButton)
    }

    private func stepNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(DS.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.black.opacity(0.55), in: Circle())
            .padding(DS.space6)
            .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: DS.space6) {
            Image(systemName: SwipeKind.flow.iconName)
                .font(DS.title2)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("No steps yet")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.textSecondary)
            // Teaching state, never "No items yet."
            Text("Record a funnel, then every swipe becomes the next step.")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
        .background(DS.glassSectionFill, in: RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous))
    }

    // MARK: - Actions

    /// Open the step with the FLOW as the browsing session, so ⌘[ / ⌘] walk
    /// the funnel in order rather than whatever grid you came from.
    private func open(_ unit: SwipeArtifactUnit) {
        guard let uuid = unit.memberSwipeUUID,
              let member = members[uuid],
              let entityId = member.id else { return }
        let order = orderedUnits.compactMap { $0.memberSwipeUUID.flatMap { members[$0]?.id } }
        SwipeStudySession.shared.begin(order: order, current: entityId)
        // The .enterFocusMode userInfo contract is byte-identical everywhere —
        // EntityType.research, an Int64 id, and the swipeGallery tab.
        NotificationCenter.default.post(
            name: .enterFocusMode,
            object: nil,
            userInfo: [
                "entityType": EntityType.research,
                "entityId": entityId,
                "commandKTab": "swipeGallery"
            ]
        )
    }

    private func loadMembers() async {
        var loaded: [String: Atom] = [:]
        for unit in orderedUnits {
            guard let uuid = unit.memberSwipeUUID,
                  let atom = try? await AtomRepository.shared.fetch(uuid: uuid),
                  !atom.isDeleted else { continue }
            loaded[uuid] = atom
        }
        members = loaded
    }
}
