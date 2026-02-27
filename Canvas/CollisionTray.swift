// CosmoOS/Canvas/CollisionTray.swift
// Expandable tray showing pending trisociative collisions.
// Collapsed: badge count. Expanded: vertical list of CollisionCardView items.

import SwiftUI

struct CollisionTray: View {
    @ObservedObject var engine: TrisociativeEngine
    @State private var isExpanded = false

    /// Warm gold accent matching CollisionCardView
    private let accentColor = Color(hex: "D4A574")

    var body: some View {
        VStack(spacing: 0) {
            if !engine.pendingCollisions.isEmpty {
                // Header / toggle
                collisionBadge
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isExpanded.toggle()
                        }
                    }

                // Expanded content
                if isExpanded {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(engine.pendingCollisions) { collision in
                                CollisionCardView(
                                    collision: collision,
                                    onRate: { rating in
                                        Task {
                                            await engine.rateCollision(id: collision.id, rating: rating)
                                        }
                                    },
                                    onPromote: {
                                        Task {
                                            await engine.promoteToConnection(collision: collision)
                                        }
                                    },
                                    onDismiss: {
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            engine.dismissCollision(id: collision.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    .frame(maxHeight: 600)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(width: isExpanded ? 320 : nil)
    }

    // MARK: - Badge

    private var collisionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(accentColor)

            Text("\(engine.pendingCollisions.count) Collision\(engine.pendingCollisions.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.text)

            Spacer()

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(DS.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OnyxColors.Elevation.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.15), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }
}
