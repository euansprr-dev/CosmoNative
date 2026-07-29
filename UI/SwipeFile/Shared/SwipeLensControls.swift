// CosmoOS/UI/SwipeFile/Shared/SwipeLensControls.swift
// The lens pill and the "also keep as" actions.
//
// The pill exists to make an inferred decision VISIBLE and cheap to correct.
// A router that silently picks swipe-or-research reads arbitrary the first time
// it picks wrong; one that says "Research — 18 paragraphs, no call to action"
// reads like it thought about it, and tells you exactly which signal to argue
// with. Overriding writes the domain prior, so the correction is also the
// teaching.

import SwiftUI

// MARK: - Lens pill

/// The inferred lens plus its reason, with a one-click flip. Used in the Inbox
/// inspector, where an ambiguous capture is waiting to be filed.
struct SwipeLensPill: View {
    let verdict: SwipeLensVerdict
    /// nil = read-only (the decision is already made and shown for confidence).
    var onFlip: ((SwipeLens) -> Void)?

    @State private var isHovered = false

    private var other: SwipeLens {
        verdict.lens == .swipe ? .research : .swipe
    }

    var body: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: verdict.lens.iconName)
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(verdict.lens.displayName)
                .font(DS.caption.weight(.semibold))
                .foregroundStyle(DS.text)

            Text("·")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)

            // The reason is not a tooltip. It is the point of the pill, so it
            // is on the surface where a glance catches it.
            Text(verdict.reason)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)

            if let onFlip, isHovered {
                Button {
                    onFlip(other)
                } label: {
                    Text(other.displayName)
                        .font(DS.caption.weight(.medium))
                        .foregroundStyle(DS.accent)
                }
                .buttonStyle(.plain)
                .help("File as \(other.displayName.lowercased()) instead — Cosmo remembers this domain")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 24)
        .background(DS.glassInputFill, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(verdict.lens.displayName) — \(verdict.reason)")
    }

    private var tint: Color {
        verdict.lens == .swipe ? DS.entitySwipe : DS.entityResearch
    }
}

// MARK: - Also keep as

/// "Also keep as research" / "Swipe this too" — the same source, a second lens.
///
/// This is the payoff of putting both lenses on one atom: no re-fetch, no
/// duplicate row, no choosing at capture time. A source you saved for its
/// argument turns out to be beautifully built, and you say so without saving
/// it twice.
struct SwipeLensAddMenuItem: View {
    let atom: Atom
    var onChanged: (() -> Void)?

    var body: some View {
        if let missing = missingLens {
            Button {
                add(missing)
            } label: {
                Label(label(for: missing), systemImage: missing.iconName)
            }
        }
    }

    /// nil when the source already carries both.
    private var missingLens: SwipeLens? {
        let lenses = atom.swipeLenses
        if !lenses.contains(.swipe) { return .swipe }
        if !lenses.contains(.research) { return .research }
        return nil
    }

    private func label(for lens: SwipeLens) -> String {
        switch lens {
        case .swipe: return "Swipe this too"
        case .research: return "Also keep as research"
        }
    }

    private func add(_ lens: SwipeLens) {
        let uuid = atom.uuid
        let url = atom.researchMetadata?.url
        Task { @MainActor in
            guard let live = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
            let updated = live.addingLens(lens)
            _ = try? await AtomRepository.shared.update(updated)
            // An explicit choice teaches the domain prior — the correction and
            // the lesson are the same gesture.
            SwipeLensRouter.recordDecision(lens: lens, url: url)
            await RecallIndexer.shared.noteAtomChanged(uuid: uuid)
            NotificationCenter.default.post(
                name: CosmoNotification.SwipeFile.libraryDidChange, object: nil
            )
            onChanged?()
        }
    }
}

// MARK: - Menu loader

/// A context menu needs the atom, and a card model only carries a uuid.
/// This loads it lazily so a masonry of eighty cards never fetches eighty rows
/// to build menus nobody opened.
struct SwipeLensMenuLoader: View {
    let swipeUUID: String

    @State private var atom: Atom?

    var body: some View {
        Group {
            if let atom {
                SwipeLensAddMenuItem(atom: atom)
            }
        }
        .task {
            guard atom == nil else { return }
            atom = try? await AtomRepository.shared.fetch(uuid: swipeUUID)
        }
    }
}
