// CosmoOS/Sync/SyncStatusView.swift
// Minimal, non-intrusive sync status indicator
// Completely invisible during normal operation

import SwiftUI

struct SyncStatusView: View {
    @ObservedObject var syncEngine = SyncEngine.shared
    @ObservedObject var networkMonitor = NetworkMonitor.shared

    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 6) {
            // Status icon
            statusIcon
                .font(.system(size: 10))
                .foregroundColor(statusColor)

            // Status text (only when hovered or syncing)
            if isExpanded || syncEngine.syncState == .syncing {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Pending count
            if syncEngine.pendingChanges > 0 {
                Text("\(syncEngine.pendingChanges)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        )
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = isHovered
            }
        }
        .help(tooltipText)
    }

    private var statusIcon: some View {
        Group {
            switch syncEngine.syncState {
            case .idle:
                if networkMonitor.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                } else {
                    Image(systemName: "wifi.slash")
                }

            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(syncEngine.isOnline ? 360 : 0))

            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
            }
        }
    }

    private var statusColor: Color {
        switch syncEngine.syncState {
        case .idle:
            return networkMonitor.isConnected ? .green : .orange

        case .syncing:
            return .blue

        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch syncEngine.syncState {
        case .idle:
            if !networkMonitor.isConnected {
                return "Offline"
            } else if let lastSync = syncEngine.lastSyncTime {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                return "Synced \(formatter.localizedString(for: lastSync, relativeTo: Date()))"
            }
            return "Synced"

        case .syncing:
            return "Syncing..."

        case .error(let message):
            return "Error: \(message)"
        }
    }

    private var tooltipText: String {
        var lines: [String] = []

        // Connection status
        if networkMonitor.isConnected {
            lines.append("Connected via \(networkMonitor.connectionType)")
        } else {
            lines.append("Offline - changes will sync when connected")
        }

        // Last sync
        if let lastSync = syncEngine.lastSyncTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            lines.append("Last sync: \(formatter.string(from: lastSync))")
        }

        // Pending changes
        if syncEngine.pendingChanges > 0 {
            lines.append("\(syncEngine.pendingChanges) changes pending")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Minimal Sync Indicator (for toolbar)
struct MinimalSyncIndicator: View {
    @ObservedObject var syncEngine = SyncEngine.shared
    @ObservedObject var networkMonitor = NetworkMonitor.shared

    var body: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 8, height: 8)
            .help(helpText)
    }

    private var indicatorColor: Color {
        if !networkMonitor.isConnected {
            return .orange
        }

        switch syncEngine.syncState {
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        }
    }

    private var helpText: String {
        if !networkMonitor.isConnected {
            return "Offline"
        }

        switch syncEngine.syncState {
        case .idle: return "All changes synced"
        case .syncing: return "Syncing..."
        case .error(let msg): return "Sync error: \(msg)"
        }
    }
}
