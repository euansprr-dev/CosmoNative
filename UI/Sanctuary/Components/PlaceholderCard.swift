// CosmoOS/UI/Sanctuary/Components/PlaceholderCard.swift
// Graceful degradation component for disconnected data sources
// Part of Sanctuary Dimensions PRD - WP0

import SwiftUI

// MARK: - Placeholder State

enum PlaceholderState {
    case notConnected(source: String, description: String, connectAction: () -> Void)
    case syncing(source: String)
    case insufficientData(source: String, progress: Double, message: String)
    case healthy
}

// MARK: - PlaceholderCard

struct PlaceholderCard: View {
    let state: PlaceholderState
    let accentColor: Color

    var body: some View {
        Group {
            switch state {
            case .notConnected(let source, let description, let connectAction):
                notConnectedView(source: source, description: description, connectAction: connectAction)
            case .syncing(let source):
                syncingView(source: source)
            case .insufficientData(let source, let progress, let message):
                insufficientDataView(source: source, progress: progress, message: message)
            case .healthy:
                EmptyView()
            }
        }
    }

    // MARK: - Not Connected

    @ViewBuilder
    private func notConnectedView(source: String, description: String, connectAction: @escaping () -> Void) -> some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(accentColor.opacity(0.6))

            VStack(spacing: SanctuaryLayout.Spacing.xs) {
                Text(source)
                    .font(SanctuaryTypography.titleSmall)
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text(description)
                    .font(SanctuaryTypography.bodySmall)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Button(action: connectAction) {
                Text("Connect \(source)")
                    .font(SanctuaryTypography.label)
                    .foregroundColor(.white)
                    .padding(.horizontal, SanctuaryLayout.Spacing.md)
                    .padding(.vertical, SanctuaryLayout.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.sm)
                            .fill(accentColor.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                .fill(SanctuaryColors.Glass.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                        .stroke(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Syncing

    @ViewBuilder
    private func syncingView(source: String) -> some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
                .scaleEffect(0.9)

            VStack(spacing: SanctuaryLayout.Spacing.xs) {
                Text("Syncing \(source)")
                    .font(SanctuaryTypography.titleSmall)
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text("First sync in progress...")
                    .font(SanctuaryTypography.bodySmall)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                .fill(SanctuaryColors.Glass.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                        .stroke(SanctuaryColors.Glass.borderSubtle, lineWidth: 1)
                )
        )
    }

    // MARK: - Insufficient Data

    @ViewBuilder
    private func insufficientDataView(source: String, progress: Double, message: String) -> some View {
        VStack(spacing: SanctuaryLayout.Spacing.md) {
            // Partial progress ring
            ZStack {
                Circle()
                    .stroke(SanctuaryColors.Glass.border, lineWidth: 3)
                    .frame(width: 40, height: 40)

                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(progress * 100))%")
                    .font(SanctuaryTypography.micro)
                    .foregroundColor(SanctuaryColors.Text.secondary)
            }

            VStack(spacing: SanctuaryLayout.Spacing.xs) {
                Text(source)
                    .font(SanctuaryTypography.titleSmall)
                    .foregroundColor(SanctuaryColors.Text.primary)

                Text(message)
                    .font(SanctuaryTypography.bodySmall)
                    .foregroundColor(SanctuaryColors.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SanctuaryLayout.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                .fill(SanctuaryColors.Glass.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: SanctuaryLayout.CornerRadius.card)
                        .stroke(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct PlaceholderCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            PlaceholderCard(
                state: .notConnected(
                    source: "Apple Health",
                    description: "Connect to track HRV, sleep, and recovery metrics",
                    connectAction: {}
                ),
                accentColor: SanctuaryColors.physiological
            )

            PlaceholderCard(
                state: .syncing(source: "Apple Health"),
                accentColor: SanctuaryColors.physiological
            )

            PlaceholderCard(
                state: .insufficientData(
                    source: "Sleep Data",
                    progress: 0.4,
                    message: "More data in 3 days"
                ),
                accentColor: SanctuaryColors.physiological
            )
        }
        .padding()
        .background(SanctuaryColors.Background.void)
    }
}
#endif
