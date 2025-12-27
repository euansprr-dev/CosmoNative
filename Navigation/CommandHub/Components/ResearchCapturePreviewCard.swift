// CosmoOS/Navigation/CommandHub/Components/ResearchCapturePreviewCard.swift
// Premium “capturing research” card shown inside the Command Hub grid.

import SwiftUI
import AppKit

struct ResearchCapturePreviewCard: View {
    let state: CommandHubCaptureController.State
    let onAction: () -> Void

    @State private var isHovered = false

    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 180

    var body: some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                // For failures we provide explicit CTA buttons (avoids double-trigger with nested buttons).
                if case .failed = state { return }
                onAction()
            }
        .onHover { hovering in
            withAnimation(HubSprings.hover) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            accentSeam
                .frame(height: 3)

            VStack(alignment: .leading, spacing: 10) {
                headerRow

                switch state {
                case .validating:
                    validatingBody
                case .capturing(let capture):
                    capturingBody(capture)
                case .duplicate:
                    duplicateBody
                case .failed(let failure):
                    failedBody(failure)
                default:
                    validatingBody
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: isHovered ? Color.black.opacity(0.10) : Color.black.opacity(0.06), radius: isHovered ? 12 : 6, y: isHovered ? 4 : 2)
        .shadow(color: accentColor.opacity(isHovered ? 0.14 : 0.08), radius: 14, y: 0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: isHovered ? -2 : 0)
    }

    private var accentColor: Color {
        switch state {
        case .failed:
            return CosmoColors.coral
        case .duplicate:
            return CosmoColors.emerald
        case .capturing(let capture):
            return color(for: capture.urlType)
        default:
            return CosmoColors.lavender
        }
    }

    private func color(for type: URLType) -> Color {
        switch type {
        case .youtube: return CosmoColors.softRed
        case .twitter: return CosmoColors.skyBlue
        case .loom: return Color(hex: "#625DF5")
        case .pdf: return CosmoColors.coral
        case .website: return CosmoColors.emerald
        }
    }

    private func icon(for type: URLType) -> String {
        switch type {
        case .youtube: return "play.rectangle.fill"
        case .twitter: return "bubble.left.fill"
        case .loom: return "video.bubble.fill"
        case .pdf: return "doc.fill"
        case .website: return "globe"
        }
    }

    private var accentSeam: some View {
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.5)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.98), CosmoColors.softWhite.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                isHovered ? accentColor.opacity(0.42) : CosmoColors.glassGrey.opacity(0.45),
                lineWidth: 1
            )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: headerIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CosmoColors.textPrimary)
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(CosmoColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var headerIcon: String {
        switch state {
        case .failed:
            return "exclamationmark.triangle.fill"
        case .duplicate:
            return "checkmark.seal.fill"
        case .capturing(let capture):
            return icon(for: capture.urlType)
        default:
            return "sparkles"
        }
    }

    private var headerTitle: String {
        switch state {
        case .failed:
            return "Capture failed"
        case .duplicate:
            return "Already saved"
        case .capturing:
            return "Capturing…"
        default:
            return "Preparing…"
        }
    }

    private var headerSubtitle: String {
        switch state {
        case .duplicate:
            return "Click to open"
        case .failed:
            return "Click to retry"
        case .capturing:
            return "Processing in the background"
        default:
            return "Checking your library"
        }
    }

    // MARK: - Bodies

    private var validatingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShimmerSkeletonBlock(height: 14, cornerRadius: 6)
            ShimmerSkeletonBlock(height: 10, cornerRadius: 6)
            ShimmerSkeletonBlock(height: 10, cornerRadius: 6)

            HStack(spacing: 8) {
                ShimmerSkeletonBlock(height: 8, cornerRadius: 6)
            }
            .padding(.top, 6)

            Text("Detecting source & checking duplicates…")
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
                .lineLimit(2)
        }
    }

    private func capturingBody(_ capture: CommandHubCaptureController.Capture) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(capture.titleHint)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)
                .lineLimit(2)

            Text(domain(from: capture.url))
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 6) {
                Text(capture.stepLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmoColors.textSecondary)
                    .lineLimit(1)

                CaptureProgressBar(progress: capture.progress, tint: accentColor)
                    .frame(height: 6)
            }

            Text("You can keep searching — this will appear as soon as it’s ready.")
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
                .lineLimit(2)
        }
    }

    private var duplicateBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This URL is already in your Research library.")
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.textSecondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 12))
                Text("Open it")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(CosmoColors.emerald)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CosmoColors.emerald.opacity(0.10), in: Capsule())

            Text("No duplicates created.")
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
        }
    }

    private func failedBody(_ failure: CommandHubCaptureController.Failure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(failure.titleHint)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(CosmoColors.textPrimary)
                .lineLimit(2)

            Text(domain(from: failure.url))
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textTertiary)
                .lineLimit(1)

            Text(failure.message)
                .font(.system(size: 10))
                .foregroundColor(CosmoColors.textSecondary)
                .lineLimit(3)

            if isYtDlpMissing(failure.message) {
                HStack(spacing: 8) {
                    Button {
                        copyToClipboard("brew install yt-dlp")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                            Text("Copy install")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(CosmoColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CosmoColors.glassGrey.opacity(0.25), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAction()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                            Text("Retry")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(CosmoColors.coral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CosmoColors.coral.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Text("YouTube capture needs `yt-dlp` installed. Once installed, hit Retry.")
                    .font(.system(size: 10))
                    .foregroundColor(CosmoColors.textTertiary)
                    .lineLimit(2)
            } else {
                Button {
                    onAction()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                        Text("Retry")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(CosmoColors.coral)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CosmoColors.coral.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func domain(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func isYtDlpMissing(_ message: String) -> Bool {
        message.lowercased().contains("yt-dlp")
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct CaptureProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CosmoColors.glassGrey.opacity(0.35))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geo.size.width * CGFloat(progress), 6))
                    .animation(.easeOut(duration: 0.18), value: progress)
            }
        }
        .clipShape(Capsule())
    }
}

private struct ShimmerSkeletonBlock: View {
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var phase: CGFloat = -0.6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(CosmoColors.mistGrey.opacity(0.55))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.38),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .rotationEffect(.degrees(18))
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: geo.size.width * phase)
                    .blendMode(.plusLighter)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .frame(width: geo.size.width, height: geo.size.height)
                    )
                }
            }
            .frame(height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

