// CosmoOS/Components/GlobalStatusIndicator.swift
// Global save/loading indicator pill - reusable across the entire app
// Appears bottom-right with smooth animations

import SwiftUI

// MARK: - Status State
enum GlobalStatusState: Equatable {
    case idle
    case saving
    case saved
    case loading(String?)
    case error(String)

    var isVisible: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

// MARK: - Global Status Service
@MainActor
final class GlobalStatusService: ObservableObject {
    static let shared = GlobalStatusService()

    @Published private(set) var state: GlobalStatusState = .idle

    private var dismissTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Show saving indicator
    func showSaving() {
        dismissTask?.cancel()
        state = .saving
    }

    /// Show saved indicator (auto-dismisses after delay)
    func showSaved() {
        dismissTask?.cancel()
        state = .saved
        scheduleDismiss(after: 2.0)
    }

    /// Show loading indicator with optional message
    func showLoading(_ message: String? = nil) {
        dismissTask?.cancel()
        state = .loading(message)
    }

    /// Show error indicator (auto-dismisses after delay)
    func showError(_ message: String) {
        dismissTask?.cancel()
        state = .error(message)
        scheduleDismiss(after: 3.0)
    }

    /// Dismiss the indicator
    func dismiss() {
        dismissTask?.cancel()
        state = .idle
    }

    // MARK: - Private

    private func scheduleDismiss(after seconds: Double) {
        dismissTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                state = .idle
            } catch {
                // Cancelled
            }
        }
    }
}

// MARK: - Global Status Pill View
struct GlobalStatusPill: View {
    @ObservedObject private var service = GlobalStatusService.shared

    var body: some View {
        Group {
            if service.state.isVisible {
                pillContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: service.state)
    }

    @ViewBuilder
    private var pillContent: some View {
        HStack(spacing: 8) {
            iconView
            textView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(backgroundView)
        .shadow(color: shadowColor, radius: 12, y: 4)
    }

    @ViewBuilder
    private var iconView: some View {
        switch service.state {
        case .saving, .loading:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.emerald)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.coral)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var textView: some View {
        switch service.state {
        case .saving:
            Text("Saving...")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textSecondary)
        case .saved:
            Text("Saved")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.emerald)
        case .loading(let message):
            Text(message ?? "Loading...")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textSecondary)
        case .error(let message):
            Text(message)
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.coral)
                .lineLimit(1)
        case .idle:
            EmptyView()
        }
    }

    private var backgroundView: some View {
        Capsule()
            .fill(CosmoColors.softWhite)
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var borderColor: Color {
        switch service.state {
        case .saved:
            return CosmoColors.emerald.opacity(0.3)
        case .error:
            return CosmoColors.coral.opacity(0.3)
        default:
            return CosmoColors.glassGrey.opacity(0.4)
        }
    }

    private var shadowColor: Color {
        switch service.state {
        case .saved:
            return CosmoColors.emerald.opacity(0.15)
        case .error:
            return CosmoColors.coral.opacity(0.15)
        default:
            return CosmoColors.glassGrey.opacity(0.3)
        }
    }
}
