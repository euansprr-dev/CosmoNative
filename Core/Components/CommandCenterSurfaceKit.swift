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
            Text(label)
                .font(DS.smallCaps)
                .foregroundStyle(tint ?? DS.giltMuted)
                .lineLimit(1)

            if let detail {
                Text(detail)
                    .font(DS.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle((tint ?? DS.textMuted).opacity(tint == nil ? 1 : 0.62))
                    .contentTransition(.numericText())
            }

            // The ledger rule — the Mac's anchoring line to the right edge.
            Rectangle()
                .fill(DS.commandCenterSeparator)
                .frame(height: 0.5)
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
