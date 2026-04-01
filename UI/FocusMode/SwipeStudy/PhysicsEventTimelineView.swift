// CosmoOS/UI/FocusMode/SwipeStudy/PhysicsEventTimelineView.swift
// Horizontal visual timeline showing physics events positioned across slides

import SwiftUI

struct PhysicsEventTimelineView: View {
    let events: PhysicsEvents
    let totalSlides: Int
    @Binding var selectedSlide: Int?
    @State private var selectedEvent: EventMarker?
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            sectionHeader
            timelineRuler
            selectedEventDetail
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMedium).stroke(DS.border, lineWidth: 1))
        .dsRestingShadow()
        .onAppear { withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true } }
    }

    // MARK: - Header

    @ViewBuilder
    private var sectionHeader: some View {
        HStack(spacing: DS.space6) {
            Text("PHYSICS EVENTS")
                .font(DS.caption)
                .tracking(1.2)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Text("\(eventMarkers.count) events")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Event Pills Row

    @ViewBuilder
    private var timelineRuler: some View {
        FlowLayout(spacing: DS.space8) {
            ForEach(Array(eventMarkers.enumerated()), id: \.element.id) { index, marker in
                eventPill(marker: marker, index: index)
            }
        }
    }

    @ViewBuilder
    private func eventPill(marker: EventMarker, index: Int) -> some View {
        let isSelected = selectedEvent?.id == marker.id

        Button {
            withAnimation(ProMotionSprings.snappy) {
                selectedEvent = isSelected ? nil : marker
                selectedSlide = isSelected ? nil : marker.slide
            }
        } label: {
            HStack(spacing: DS.space6) {
                Image(systemName: marker.icon)
                    .font(DS.caption)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(marker.color, in: Circle())
                    .accessibilityLabel(marker.label)

                VStack(alignment: .leading, spacing: 1) {
                    Text(marker.label)
                        .font(DS.caption)
                        .foregroundStyle(DS.text)
                    Text("@slide \(marker.slide)")
                        .font(DS.caption2)
                        .monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                }
            }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space6)
            .background(
                isSelected ? marker.color.opacity(0.1) : DS.surfaceHover,
                in: RoundedRectangle(cornerRadius: DS.radiusSmall)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .stroke(isSelected ? marker.color.opacity(0.4) : DS.border, lineWidth: 1)
            )
            .opacity(hasAppeared ? 1 : 0)
            .animation(ProMotionSprings.staggered(index: index), value: hasAppeared)
        }
        .buttonStyle(.plain)
    }

    private struct FlowLayout: Layout {
        var spacing: CGFloat = 4
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            layout(proposal: proposal, subviews: subviews).size
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
            for (i, pos) in result.positions.enumerated() where i < subviews.count {
                subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
            }
        }
        private struct R { var size: CGSize; var positions: [CGPoint] }
        private func layout(proposal: ProposedViewSize, subviews: Subviews) -> R {
            let maxW = proposal.width ?? .infinity
            var positions: [CGPoint] = []; var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
            for sv in subviews {
                let s = sv.sizeThatFits(.unspecified)
                if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
                positions.append(CGPoint(x: x, y: y)); rowH = max(rowH, s.height); x += s.width + spacing
            }
            return R(size: CGSize(width: maxW, height: y + rowH), positions: positions)
        }
    }

    // MARK: - Selected Event Detail

    @ViewBuilder
    private var selectedEventDetail: some View {
        if let marker = selectedEvent {
            VStack(alignment: .leading, spacing: DS.space6) {
                HStack(spacing: DS.space6) {
                    Image(systemName: marker.icon)
                        .font(DS.callout)
                        .foregroundStyle(marker.color)
                        .accessibilityHidden(true)
                    Text(marker.label)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                    Text("@slide \(marker.slide)")
                        .font(DS.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                }
                if let detail = marker.detail, !detail.isEmpty {
                    Text(detail)
                        .font(DS.callout)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let secondary = marker.secondaryDetail, !secondary.isEmpty {
                    Text(secondary)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(marker.color.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(marker.color.opacity(0.15), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Helpers

    private var eventMarkers: [EventMarker] {
        var markers: [EventMarker] = []
        if let brk = events.symmetryBreak, let slide = brk.slideNumber, slide > 0 {
            markers.append(EventMarker(
                id: "symmetry", slide: slide, icon: "bolt.fill", color: DS.orange,
                label: "Symmetry Break", shortLabel: "Break",
                detail: brk.whatBreaks, secondaryDetail: brk.whyDevastating
            ))
        }
        if let pt = events.phaseTransition, let slide = pt.slideNumber, slide > 0 {
            let shift = [pt.frameBefore, pt.frameAfter].compactMap { $0 }.joined(separator: " → ")
            markers.append(EventMarker(
                id: "phase", slide: slide, icon: "arrow.triangle.2.circlepath", color: DS.info,
                label: "Phase Transition", shortLabel: "Phase",
                detail: shift.isEmpty ? nil : shift, secondaryDetail: pt.recontextualization
            ))
        }
        if let pg = events.peakGravity, let slide = pg.slideNumber, slide > 0 {
            markers.append(EventMarker(
                id: "gravity", slide: slide, icon: "tornado", color: DS.entitySwipe,
                label: "Peak Gravity", shortLabel: "Gravity",
                detail: pg.activeLoops.map { "\($0) active loops" }, secondaryDetail: nil
            ))
        }
        if let er = events.energyResolution {
            let slide = events.peakGravity?.slideNumber ?? totalSlides
            markers.append(EventMarker(
                id: "energy", slide: slide, icon: "equal.circle.fill",
                color: er.proportional == true ? DS.green : DS.red,
                label: "Energy Resolution", shortLabel: "Energy",
                detail: er.assessment, secondaryDetail: nil
            ))
        }
        return markers.sorted { $0.slide < $1.slide }
    }
}

// MARK: - Event Marker Model

private struct EventMarker: Identifiable, Equatable {
    let id: String
    let slide: Int
    let icon: String
    let color: Color
    let label: String
    let shortLabel: String
    let detail: String?
    let secondaryDetail: String?

    static func == (lhs: EventMarker, rhs: EventMarker) -> Bool { lhs.id == rhs.id }
}
