// CosmoOS/Core/Components/OfflineReassurancePill.swift
// The quiet promise: launching offline (or with an expired session) never
// hides the workspace — one small glass notice says your work is safe and
// will sync, then gets out of the way. iOS twin: CosmoiOS/Sources/Shared/
// OfflineReassurancePill.swift — same voice, same anatomy.

import SwiftUI

struct OfflineReassurancePill: View {
    enum Variant: Equatable {
        /// Signed in (or local-only) but no network at launch. Auto-dismisses.
        case offline(email: String?)
        /// The server rejected the session — workspace intact, sync paused.
        case sessionExpired
    }

    let variant: Variant
    var onTap: (() -> Void)?

    @State private var isHovered = false

    private var icon: String {
        switch variant {
        case .offline: return "wifi.slash"
        case .sessionExpired: return "person.crop.circle.badge.exclamationmark"
        }
    }

    private var title: String {
        switch variant {
        case .offline: return "You're offline"
        case .sessionExpired: return "Session expired"
        }
    }

    private var subtitle: String {
        switch variant {
        case .offline(let email):
            if let email {
                return "Signed in as \(email) — your work is saved here and syncs when you reconnect."
            }
            return "Your work is saved here and syncs when you reconnect."
        case .sessionExpired:
            return "Your work is safe here. Sign in to resume sync."
        }
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: icon)
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DS.footnote.weight(.semibold))
                        .foregroundStyle(DS.text)
                    Text(subtitle)
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if case .sessionExpired = variant {
                    Image(systemName: "chevron.right")
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, DS.space10)
            .padding(.horizontal, DS.space16)
            .frame(maxWidth: 380, alignment: .leading)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        .scaleEffect(isHovered && onTap != nil ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(variant == .sessionExpired ? "Sign in with Apple to resume sync" : "Cosmo works fully offline")
        .disabled(onTap == nil)
        .accessibilityElement(children: .combine)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// MainView's one mount point: the launch-offline notice (once, 6s) and the
/// expired-session re-auth notice (until resolved). Expired outranks offline.
struct OfflineReassuranceOverlay: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var showOfflinePill = false
    @State private var offlinePillShown = false

    private var auth: SupabaseAuthService { .shared }

    private var sessionExpired: Bool {
        !auth.isSignedIn && auth.workspaceMode == .cloud
    }

    var body: some View {
        VStack {
            if sessionExpired {
                OfflineReassurancePill(variant: .sessionExpired) {
                    Task { await SupabaseAuthService.shared.signInWithApple() }
                }
                .padding(.top, DS.space12)
            } else if showOfflinePill {
                OfflineReassurancePill(variant: .offline(email: auth.userEmail))
                    .padding(.top, DS.space12)
            }
            Spacer()
        }
        .animation(ProMotionSprings.modal, value: sessionExpired)
        .task { await presentOfflinePillIfNeeded() }
    }

    private func presentOfflinePillIfNeeded() async {
        guard !offlinePillShown else { return }
        offlinePillShown = true
        // Let launch settle (and NWPathMonitor deliver its first path).
        try? await Task.sleep(for: .milliseconds(1200))
        guard !network.isConnected, auth.isSignedIn else { return }
        withAnimation(ProMotionSprings.modal) { showOfflinePill = true }
        try? await Task.sleep(for: .seconds(6))
        withAnimation(ProMotionSprings.gentle) { showOfflinePill = false }
    }
}
