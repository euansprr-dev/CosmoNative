// CosmoOS/Canvas/PortalBlockView.swift
// Portal — a block that is a window into another thinkspace: a live (cached)
// miniature of the target, recessed like a window, never a glowing vortex.
// Double-click to travel; the trail brings you back.

import SwiftUI

// MARK: - Factory

extension CanvasBlock {
    /// Create a portal block targeting another thinkspace.
    /// The target's uuid doubles as the block's entityUuid, so one canvas
    /// holds at most one portal per destination.
    static func portalBlock(position: CGPoint, targetThinkspaceId: String, targetName: String) -> CanvasBlock {
        CanvasBlock(
            position: position,
            size: CGSize(width: 300, height: 210),
            entityType: .portal,
            entityId: -1,
            entityUuid: targetThinkspaceId,
            title: targetName,
            subtitle: nil,
            metadata: [:]
        )
    }
}

// MARK: - Portal Block

struct PortalBlockView: View {
    let block: CanvasBlock

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    private var targetThinkspaceId: String { block.entityUuid }

    private var target: Thinkspace? {
        ThinkspaceManager.shared.thinkspaces.first { $0.id == targetThinkspaceId }
    }

    private var targetName: String {
        target?.name ?? (block.title.isEmpty ? "Thinkspace" : block.title)
    }

    private var targetAccent: Color {
        target?.accentColor ?? DS.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            windowBody
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targetAccent.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(isHovered ? 1.01 : 1)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
        }
        .onTapGesture(count: 2, perform: travel)
        .contextMenu {
            Button {
                travel()
            } label: {
                Label("Open \(targetName)", systemImage: "arrow.up.right")
            }
            .disabled(target == nil)

            Divider()

            Button(role: .destructive) {
                NotificationCenter.default.post(
                    name: .removeBlock,
                    object: nil,
                    userInfo: ["blockId": block.id]
                )
            } label: {
                Label("Remove Portal", systemImage: "trash")
            }
        }
        .help("Open \(targetName) (double-click)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Portal to \(targetName)")
        .accessibilityAddTraits(.isButton)
        .task(id: targetThinkspaceId) {
            thumbnail = ThinkspaceThumbnailService.shared.cachedThumbnail(for: targetThinkspaceId)
            thumbnail = await ThinkspaceThumbnailService.shared.thumbnail(
                for: targetThinkspaceId,
                size: CGSize(width: 300, height: 180)
            ) ?? thumbnail
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(targetAccent)
                .frame(width: 6, height: 6)

            Text(targetName)
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(DS.surfaceElevated)
    }

    // MARK: Window body

    private var windowBody: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(isHovered ? 1 : 0.96)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .top) {
            // Recessed cue — a portal is conceptually a window into elsewhere.
            LinearGradient(
                colors: [.black.opacity(0.07), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: target == nil ? "questionmark.square.dashed" : "rectangle.3.group")
                .font(DS.title2)
                .foregroundStyle(DS.textMuted.opacity(0.5))
            Text(target == nil ? "Lost destination" : "Empty thinkspace")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: Travel

    private func travel() {
        guard target != nil else { return }
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.navigateToThinkspaceById,
            object: nil,
            userInfo: ["thinkspaceId": targetThinkspaceId]
        )
    }
}

// MARK: - Target Picker

/// The small searchable popover for choosing a portal destination.
struct PortalTargetPicker: View {
    var excludeThinkspaceId: String?
    let onPick: (Thinkspace) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var manager = ThinkspaceManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var appeared = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerLabel
            searchField
            resultsList
        }
        .padding(14)
        .frame(width: 320)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 18)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            searchFocused = true
            withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.bouncy) {
                appeared = true
            }
        }
        .onExitCommand(perform: onDismiss)
    }

    private var headerLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.forward.app")
                .font(DS.caption)
                .foregroundStyle(DS.accent)
            Text("Portal to…")
                .font(DS.caption)
                .tracking(0.3)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var searchField: some View {
        TextField("Find a thinkspace", text: $query)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .focused($searchFocused)
            .onSubmit {
                if let first = filtered.first { onPick(first) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .dsGlassInput(isFocused: searchFocused, cornerRadius: 9)
            .accessibilityLabel("Find a thinkspace")
    }

    private var filtered: [Thinkspace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.thinkspaces
            .filter { $0.id != excludeThinkspaceId }
            .filter { trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    private var resultsList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 1) {
                ForEach(filtered) { thinkspace in
                    PortalTargetRow(thinkspace: thinkspace) { onPick(thinkspace) }
                }
            }
        }
        .frame(maxHeight: 280)
        .scrollIndicators(.hidden)
    }
}

private struct PortalTargetRow: View {
    let thinkspace: Thinkspace
    let onPick: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 8) {
                Circle()
                    .fill(thinkspace.accentColor)
                    .frame(width: 6, height: 6)
                Text(thinkspace.name)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(thinkspace.blockCount)")
                    .font(DS.caption.monospacedDigit())
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? DS.accentSoft : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityLabel("Portal to \(thinkspace.name)")
    }
}
