// Core/Components/CommandCenterSurfaceKit.swift
// The cross-platform surface system, macOS accent (peakui references/surfaces.md):
// one section-header voice with live counts, and the entrance cascade. Twin of
// the iPhone's CosmoSurfaceKit — grammar identical, manners native (the header
// keeps the Mac's ledger rule; hover and tooltips live in callers).

import SwiftUI

// MARK: - Section header

/// The one section-header voice: small-caps label (gilt by default, tinted for
/// semantic sections like Overdue), a quiet trailing count that ticks with
/// `.numericText()`, the Mac's ledger rule filling to the right edge, and an
/// optional trailing action slot (Reschedule, sort) docked in the header.
struct CosmoSectionHeader<Trailing: View>: View {
    let label: String
    var detail: String? = nil
    /// Semantic tint (Overdue red, cluster colors); nil = standard gilt.
    var tint: Color? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.space6) {
            // Tracked: 10pt small caps jam without letterspace. giltInk, not
            // giltMuted: a header carrying TEXT must clear AA and must never
            // be quieter than the metadata it introduces.
            Text(label)
                .font(DS.smallCaps)
                .tracking(DS.smallCapsTracking)
                .foregroundStyle(tint ?? DS.giltInk)
                .lineLimit(1)

            if let detail {
                // Full strength, no alpha: subordination is already carried
                // by size and case — an opacity on top pushed the SEMANTIC
                // counts (Overdue's number) to 2.4:1, the faintest integers
                // on the page. Rungs, never alphas.
                Text(detail)
                    .font(DS.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(tint ?? DS.giltInk)
                    .contentTransition(.numericText())
            }

            // The ledger rule — anchors the label, then DEPARTS over a FIXED
            // 64pt terminus (a fractional fade dissolved over ~500pt in the
            // ledger and ~110pt in the timeline, side by side — the same
            // voice must end the same way at every width).
            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
                .mask(
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 64)
                    }
                )
                .padding(.leading, DS.space8)

            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

extension CosmoSectionHeader where Trailing == EmptyView {
    init(label: String, detail: String? = nil, tint: Color? = nil) {
        self.init(label: label, detail: detail, tint: tint, trailing: { EmptyView() })
    }
}

// MARK: - Page rule

/// The page's ONE structural rule voice: 0.5pt `commandCenterSeparator` that
/// anchors on the left and departs over a fixed 64pt terminus — the same
/// ending at every width. Used by the masthead and the hero/ledger seam;
/// `CosmoSectionHeader` draws the identical anatomy inline beside its label.
struct CosmoPageRule: View {
    var body: some View {
        Rectangle()
            .fill(DS.commandCenterSeparator)
            .frame(height: 0.5)
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 64)
                }
            )
    }
}

// MARK: - Entrance cascade

/// The page assembles for you: sections rise in top-to-bottom on first load.
/// Reduce Motion keeps the fade, drops the rise. An arrival, not a loop —
/// reloads never re-run it.
struct CascadeIn: ViewModifier {
    let on: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 6)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : ProMotionSprings.staggered(index: index, baseDelay: 0.06),
                value: on
            )
    }
}

extension View {
    func cascadeIn(_ on: Bool, index: Int) -> some View {
        modifier(CascadeIn(on: on, index: index))
    }
}
