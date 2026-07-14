// CosmoOS/Onboarding/WelcomeGateView.swift
// The First Constellation — the threshold of the workspace. A living, seeded
// star-chart (ConstellationField) behind one piece of floating glass holding
// the only two choices: continue with Apple, or continue offline and sync
// later. Pointer parallax gives the sky depth; on sign-in the constellation
// converges and the glass dissolves into the app (worldSwitch).
// Offline-aware: with no network the Apple button quiets and the offline
// path promotes to the hero position. iOS twin: Onboarding/WelcomeView.

import SwiftUI

/// The one integration point for MainView: mounts the gate while this Mac
/// holds no workspace, and holds it up through the departure choreography.
struct WelcomeGateOverlay: View {
    @State private var holdForDeparture = false

    private var auth: SupabaseAuthService { .shared }

    /// `-cosmo-demo-welcome` forces the threshold over any account state —
    /// for screenshots only (DEBUG twin of the iOS flag).
    private var demoForced: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-cosmo-demo-welcome")
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            if demoForced || auth.showsWelcomeGate || holdForDeparture {
                WelcomeGateView(holdForDeparture: $holdForDeparture)
                    .transition(.opacity)
            }
        }
        .animation(ProMotionSprings.worldSwitch, value: auth.showsWelcomeGate || holdForDeparture)
    }
}

struct WelcomeGateView: View {
    @Binding var holdForDeparture: Bool

    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false
    @State private var convergeStartedAt: Date?
    @State private var isDeparting = false
    @State private var parallax: CGSize = .zero

    private var auth: SupabaseAuthService { .shared }
    private var isOffline: Bool { !network.isConnected }
    private var isSigningIn: Bool {
        if case .signingIn = auth.authState { return true }
        return false
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DS.bg.ignoresSafeArea()

                ConstellationFieldView(parallax: parallax, convergeStartedAt: convergeStartedAt)
                    .filmGrain()
                    .ignoresSafeArea()

                thresholdPanel
                    .frame(width: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onContinuousHover { phase in
                guard !reduceMotion else { return }
                trackPointer(phase, in: proxy.size)
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(ProMotionSprings.cardEntrance) { hasAppeared = true }
        }
    }

    // MARK: - The glass threshold

    private var thresholdPanel: some View {
        VStack(spacing: DS.space20) {
            VStack(spacing: DS.space8) {
                wordmark
                Text("A quiet place for everything you think.")
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(ProMotionSprings.cascade(index: 6), value: hasAppeared)
            }
            .padding(.top, DS.space8)

            VStack(spacing: DS.space10) {
                appleButton
                offlineButton
            }

            statusLine
        }
        .padding(DS.space24)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
        // The nearest parallax layer drifts against the sky — depth you can feel.
        .offset(x: parallax.width * -0.5, y: parallax.height * -0.5)
        .scaleEffect(isDeparting ? 0.94 : (hasAppeared ? 1 : 0.98))
        .opacity(isDeparting ? 0 : (hasAppeared ? 1 : 0))
        .animation(ProMotionSprings.modal, value: isDeparting)
        .animation(ProMotionSprings.cardEntrance, value: hasAppeared)
    }

    /// "Cosmo", glyph by glyph — the wordmark assembles like the sky behind it.
    private var wordmark: some View {
        HStack(spacing: 0) {
            ForEach(Array("Cosmo".enumerated()), id: \.offset) { index, glyph in
                Text(String(glyph))
                    .font(DS.displaySerif)
                    .foregroundStyle(DS.text)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 6)
                    .animation(ProMotionSprings.cascade(index: index), value: hasAppeared)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cosmo")
    }

    // MARK: - Actions

    private var appleButton: some View {
        WelcomeGateButton(
            isProminent: true,
            isDefaultAction: true,
            help: isOffline ? "Sign in needs a connection — continue offline below" : "Sign in with your Apple ID (Return)"
        ) {
            Task { await signInWithApple() }
        } label: {
            HStack(spacing: DS.space8) {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                        .tint(colorScheme == .dark ? .black : .white)
                    Text("Signing in…")
                } else {
                    Image(systemName: "applelogo")
                        .accessibilityHidden(true)
                    Text("Continue with Apple")
                }
            }
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        }
        .disabled(isOffline || isSigningIn || isDeparting)
        .opacity(isOffline ? 0.35 : 1)
        .animation(ProMotionSprings.gentle, value: isOffline)
    }

    /// Offline, this is the hero: the border arrives and the label firms up.
    private var offlineButton: some View {
        WelcomeGateButton(
            isProminent: false,
            isOutlined: isOffline,
            help: "Work fully offline — everything syncs when you sign in later"
        ) {
            Task { await continueOffline() }
        } label: {
            Text("Continue offline — sync later")
                .foregroundStyle(isOffline ? DS.text : DS.textSecondary)
        }
        .disabled(isDeparting)
        .animation(ProMotionSprings.gentle, value: isOffline)
    }

    // MARK: - Status line

    @ViewBuilder private var statusLine: some View {
        if case .error(let message) = auth.authState {
            Text(message)
                .font(DS.footnote)
                .foregroundStyle(DS.red)
                .multilineTextAlignment(.center)
        } else {
            Text(isOffline
                 ? "You're offline — start working now. Everything syncs when you reconnect."
                 : "Signs into the same account on your other devices.")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .animation(ProMotionSprings.gentle, value: isOffline)
        }
    }

    // MARK: - Choreography

    private func trackPointer(_ phase: HoverPhase, in size: CGSize) {
        switch phase {
        case .active(let point):
            guard size.width > 0, size.height > 0 else { return }
            let target = CGSize(
                width: (point.x / size.width - 0.5) * 12,
                height: (point.y / size.height - 0.5) * 12
            )
            withAnimation(ProMotionSprings.gentle) { parallax = target }
        case .ended:
            withAnimation(ProMotionSprings.gentle) { parallax = .zero }
        }
    }

    private func signInWithApple() async {
        holdForDeparture = true
        await auth.signInWithApple()
        guard auth.isSignedIn else {
            holdForDeparture = false
            return
        }
        await playDeparture()
        holdForDeparture = false
    }

    private func continueOffline() async {
        holdForDeparture = true
        await playDeparture()
        auth.establishLocalWorkspace()
        holdForDeparture = false
    }

    /// The sky converges, the glass recedes, the world switches.
    private func playDeparture() async {
        guard !reduceMotion else { return }
        convergeStartedAt = Date()
        isDeparting = true
        try? await Task.sleep(for: .milliseconds(680))
    }
}

// MARK: - Gate button (hover lift + press compress, the Mac manners)

private struct WelcomeGateButton<Label: View>: View {
    var isProminent: Bool
    var isOutlined: Bool = false
    var isDefaultAction: Bool = false
    var help: String
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        button
        .buttonStyle(.plain)
        .background(fill, in: .capsule)
        .overlay(Capsule().strokeBorder(DS.text.opacity(isOutlined ? 0.22 : 0), lineWidth: 1))
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(ProMotionSprings.hover, value: isHovered)
        .onHover { isHovered = $0 }
        .help(help)
    }

    @ViewBuilder private var button: some View {
        let base = Button(action: action) {
            label()
                .font(DS.callout.weight(isProminent || isOutlined ? .semibold : .medium))
                .frame(maxWidth: .infinity)
                .frame(height: isProminent || isOutlined ? 44 : 36)
                .contentShape(.capsule)
        }
        if isDefaultAction {
            base.keyboardShortcut(.defaultAction)
        } else {
            base
        }
    }

    private var fill: Color {
        guard isProminent else {
            return isHovered ? DS.text.opacity(0.05) : .clear
        }
        let base = colorScheme == .dark ? Color.white : Color.black
        return isHovered ? base.opacity(0.88) : base
    }
}
