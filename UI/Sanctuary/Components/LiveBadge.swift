// CosmoOS/UI/Sanctuary/Components/LiveBadge.swift
// Live Badge - Real-time metric status indicator for Sanctuary dimensions
// Shows live data connection status with qualitative assessment

import SwiftUI

// MARK: - Live Badge

struct LiveBadge: View {
    let metricName: String
    let value: String
    let qualitativeLabel: String
    let accentColor: Color
    let isOnline: Bool

    var body: some View {
        if isOnline {
            onlineBadge
        } else {
            offlineBadge
        }
    }

    // MARK: - Online State

    private var onlineBadge: some View {
        HStack(spacing: 8) {
            // Pulsing green dot
            ZStack {
                Circle()
                    .fill(SanctuaryColors.live.opacity(0.3))
                    .frame(width: 12, height: 12)

                Circle()
                    .fill(SanctuaryColors.live)
                    .frame(width: 6, height: 6)
            }

            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.live)
                .tracking(0.8)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 12)

            Text(metricName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SanctuaryColors.textSecondary)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(accentColor)

            Text(qualitativeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(accentColor.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(accentColor.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Offline State

    private var offlineBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SanctuaryColors.textMuted)
                .frame(width: 6, height: 6)

            Text("OFFLINE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SanctuaryColors.textMuted)
                .tracking(0.8)

            Text("Connect data in Settings")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(SanctuaryColors.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.03))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Animated Live Badge (with pulsing dot)

struct AnimatedLiveBadge: View {
    let metricName: String
    let value: String
    let qualitativeLabel: String
    let accentColor: Color
    let isOnline: Bool

    @State private var isPulsing = false

    var body: some View {
        LiveBadge(
            metricName: metricName,
            value: value,
            qualitativeLabel: qualitativeLabel,
            accentColor: accentColor,
            isOnline: isOnline
        )
        .overlay(alignment: .leading) {
            if isOnline {
                Circle()
                    .fill(SanctuaryColors.live.opacity(0.2))
                    .frame(width: 16, height: 16)
                    .scaleEffect(isPulsing ? 1.8 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)
                    .offset(x: 15)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                        ) {
                            isPulsing = true
                        }
                    }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LiveBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AnimatedLiveBadge(
                metricName: "HRV",
                value: "48ms",
                qualitativeLabel: "Good",
                accentColor: SanctuaryColors.physiological,
                isOnline: true
            )

            LiveBadge(
                metricName: "Focus",
                value: "87%",
                qualitativeLabel: "Deep",
                accentColor: SanctuaryColors.cognitive,
                isOnline: true
            )

            LiveBadge(
                metricName: "HRV",
                value: "--",
                qualitativeLabel: "",
                accentColor: SanctuaryColors.physiological,
                isOnline: false
            )
        }
        .padding(24)
        .background(SanctuaryColors.voidPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
