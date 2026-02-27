// CosmoOS/Canvas/CollisionCardView.swift
// Triangular layout showing three connected ideas with a bridging concept.
// Part of the Trisociative Collision Engine — engineered serendipity.

import SwiftUI

struct CollisionCardView: View {
    let collision: CollisionResult
    let onRate: (CollisionResult.CollisionRating) -> Void
    let onPromote: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    // MARK: - Layout Constants

    private enum Layout {
        static let cardWidth: CGFloat = 300
        static let cardHeight: CGFloat = 280
        static let triangleRadius: CGFloat = 70
        static let triangleCenterY: CGFloat = 85
        static let atomBoxSize: CGFloat = 80
        static let lineWidth: CGFloat = 1.5
    }

    /// Warm gold accent for collisions
    private let accentColor = Color(hex: "D4A574")

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Triangle area with connection lines and atom previews
            ZStack {
                // Bezier connection lines between all three
                connectionLines

                // Three atom preview boxes
                atomBox(title: collision.atomATitle, position: trianglePoint(index: 0))
                atomBox(title: collision.atomBTitle, position: trianglePoint(index: 1))
                atomBox(title: collision.atomCTitle, position: trianglePoint(index: 2))
            }
            .frame(width: Layout.cardWidth, height: 170)

            // Bridging concept
            VStack(spacing: 4) {
                Text(collision.bridgingConcept)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(collision.bridgingExplanation)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Spacer(minLength: 8)

            // Bottom action bar
            actionBar
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .frame(width: Layout.cardWidth, height: Layout.cardHeight)
        .background(OnyxColors.Elevation.floating)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(hovering ? 0.15 : 0.05), radius: 12, y: 4)
        .onHover { hovering = $0 }
    }

    // MARK: - Triangle Points

    /// Equilateral triangle points centered in the area
    private func trianglePoint(index: Int) -> CGPoint {
        let centerX = Layout.cardWidth / 2
        let centerY = Layout.triangleCenterY
        let r = Layout.triangleRadius

        switch index {
        case 0: // Top
            return CGPoint(x: centerX, y: centerY - r)
        case 1: // Bottom-left
            return CGPoint(x: centerX - r * 0.866, y: centerY + r * 0.5)
        case 2: // Bottom-right
            return CGPoint(x: centerX + r * 0.866, y: centerY + r * 0.5)
        default:
            return CGPoint(x: centerX, y: centerY)
        }
    }

    // MARK: - Connection Lines

    private var connectionLines: some View {
        Canvas { context, size in
            let points = (0..<3).map { trianglePoint(index: $0) }

            for i in 0..<3 {
                let from = points[i]
                let to = points[(i + 1) % 3]

                // Curved bezier between points
                let midX = (from.x + to.x) / 2
                let midY = (from.y + to.y) / 2
                let centerX = Layout.cardWidth / 2
                let centerY = Layout.triangleCenterY

                // Control point pulls toward center for a slight curve
                let control = CGPoint(
                    x: midX + (centerX - midX) * 0.3,
                    y: midY + (centerY - midY) * 0.3
                )

                var path = Path()
                path.move(to: from)
                path.addQuadCurve(to: to, control: control)

                // Glow
                context.stroke(
                    path,
                    with: .color(accentColor.opacity(0.2)),
                    style: StrokeStyle(lineWidth: Layout.lineWidth * 3, lineCap: .round)
                )

                // Main line
                context.stroke(
                    path,
                    with: .color(accentColor.opacity(0.5)),
                    style: StrokeStyle(lineWidth: Layout.lineWidth, lineCap: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Atom Box

    private func atomBox(title: String, position: CGPoint) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DS.text)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .frame(width: Layout.atomBoxSize, height: 44)
            .padding(.horizontal, 4)
            .background(OnyxColors.Elevation.raised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accentColor.opacity(0.2), lineWidth: 0.5)
            )
            .position(position)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            // Thumbs up
            ratingButton(
                icon: "hand.thumbsup",
                isActive: collision.userRating == .positive,
                action: { onRate(.positive) }
            )

            // Thumbs down
            ratingButton(
                icon: "hand.thumbsdown",
                isActive: collision.userRating == .negative,
                action: { onRate(.negative) }
            )

            Spacer()

            // Dismiss
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Promote to Connection
            Button(action: onPromote) {
                HStack(spacing: 4) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("Connect")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accentColor.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func ratingButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isActive ? "\(icon).fill" : icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? accentColor : DS.textMuted)
                .frame(width: 28, height: 28)
                .background(isActive ? accentColor.opacity(0.12) : Color.clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
