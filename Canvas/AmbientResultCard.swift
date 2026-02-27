// CosmoOS/Canvas/AmbientResultCard.swift
// Compact card for ambient knowledge results
// February 2026

import SwiftUI

struct AmbientResultCard: View {
    let result: AmbientResult
    let onPull: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if isHovered {
                previewRow
            }
        }
        .padding(10)
        .background(
            isHovered ? OnyxColors.Elevation.elevated : OnyxColors.Elevation.raised,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovered ? DS.borderActive : DS.border, lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: result.atomType.icon)
                .font(.system(size: 11))
                .foregroundColor(result.atomType.color)
                .frame(width: 20, height: 20)

            // Title + reason
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Text(result.relevanceReason)
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Pull button
            Button(action: onPull) {
                Text("Pull")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)

            // Dismiss button (visible on hover)
            if isHovered {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Preview Row (on hover)

    private var previewRow: some View {
        Group {
            if !result.preview.isEmpty {
                Text(result.preview)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 6)
                    .padding(.leading, 28) // Align with title
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
