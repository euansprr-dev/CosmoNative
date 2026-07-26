// CosmoOS/Canvas/ConceptMergeDropCard.swift
// The drop UI for note→concept merges (July 2026): dragging a note or sticky
// block onto a connection block on the canvas offers to merge its content —
// confirm opens the concept with the collaborator already intaking the note,
// staging bullets per section for the user's review. Cancel leaves the note
// exactly where it was dropped; nothing is destructive either way.

import SwiftUI

/// What the drag-end detector found: a mergeable source sitting on a concept.
/// Carries the drop-time source snapshot — canvas-only stickies have no atom
/// row, so the block's own text must travel with the confirm.
struct ConceptMergeDropCandidate: Identifiable, Equatable {
    let source: ConceptMergeSourceSnapshot
    /// Display title for the card (falls back to "Sticky note" etc.).
    let noteTitle: String
    let conceptBlockID: String
    let conceptUUID: String
    let conceptTitle: String
    /// Canvas-space anchor for the card (the concept block's center).
    let anchorPoint: CGPoint

    var id: String { source.uuid + conceptUUID }
    var noteType: AtomType { source.kind }
}

struct ConceptMergeDropCard: View {
    let candidate: ConceptMergeDropCandidate
    let onMerge: () -> Void
    let onCancel: () -> Void

    private var noteWord: String {
        ConceptNoteMergeComposer.kindWord(for: candidate.noteType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            HStack(spacing: DS.space8) {
                Image(systemName: "arrow.triangle.merge")
                    .font(DS.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                Text("Merge into \(candidate.conceptTitle)?")
                    .font(DS.headline)
                    .foregroundStyle(DS.text)
                    .lineLimit(2)
            }
            Text("Cosmo sorts \"\(candidate.noteTitle)\" into the board's sections as staged bullets. You review every one before it lands; the \(noteWord) itself is untouched.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.space10) {
                Spacer(minLength: 0)
                Button("Not now", action: onCancel)
                    .buttonStyle(.plain)
                    .font(DS.callout.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel merge")
                Button(action: onMerge) {
                    Text("Merge & Review")
                        .font(DS.callout.weight(.semibold))
                        .foregroundStyle(DS.textOnAccent)
                        .padding(.horizontal, DS.space12)
                        .frame(height: 30)
                        .background(DS.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .help("Open the concept with the collaborator intaking this \(noteWord)")
                .accessibilityLabel("Merge and review")
            }
        }
        .padding(DS.space16)
        .frame(width: 340)
        .background(DS.surfaceElevated)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
