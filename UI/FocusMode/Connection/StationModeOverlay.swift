// CosmoOS/UI/FocusMode/Connection/StationModeOverlay.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// Station Mode is the "deep work on one dimension" move. Double-click a station
// card in the Forge and it zooms into a full-focus presentation — the other
// seven stations dim and blur behind it, and the user can write longform on
// this single facet of the framework without distraction.

import SwiftUI

struct StationModeOverlay: View {

    @Binding var section: ConnectionSection
    let onAddItem: (RichDocument, String) -> Void
    let onEditItem: (ConnectionItem) -> Void
    let onDeleteItem: (UUID) -> Void
    let onSourceTap: (String) -> Void
    let onAcceptGhost: (GhostSuggestion) -> Void
    let onDismissGhost: (UUID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            dimmedBackdrop
            zoomedCard
            dismissButton
        }
    }

    // MARK: - Backdrop

    private var dimmedBackdrop: some View {
        DS.vellum.opacity(0.88)
            .ignoresSafeArea()
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .transition(.opacity)
    }

    // MARK: - Zoomed card

    private var zoomedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            prompt
            StationCardView(
                section: $section,
                onAddItem: onAddItem,
                onEditItem: onEditItem,
                onDeleteItem: onDeleteItem,
                onSourceTap: onSourceTap,
                onAcceptGhost: onAcceptGhost,
                onDismissGhost: onDismissGhost,
                displayMode: .focus,
                isSelected: true,
                cardWidth: 640
            )
        }
        .padding(36)
        .frame(maxWidth: 720)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DS.vellum)
                .shadow(color: Color.black.opacity(0.18), radius: 36, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.sepiaBorder, lineWidth: 0.5)
        )
        .padding(60)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(section.type.accentColor)
                .frame(width: 8, height: 8)
            Text(section.type.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(2.4)
                .foregroundStyle(section.type.accentColor)
            Spacer()
            Text("STATION MODE")
                .font(DS.smallCaps)
                .tracking(2.0)
                .foregroundStyle(DS.giltMuted)
        }
    }

    private var prompt: some View {
        Text(section.type.promptQuestion)
            .font(.system(size: 18, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(DS.inkFaded)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.inkFaded)
                .frame(width: 44, height: 44)
                .background(Circle().fill(DS.vellum.opacity(0.9)))
                .overlay(Circle().stroke(DS.sepiaBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(32)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Exit station mode")
    }
}
