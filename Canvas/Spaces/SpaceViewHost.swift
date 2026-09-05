// CosmoOS/Canvas/Spaces/SpaceViewHost.swift
// The non-canvas views of a space, hosted over the keep-alive canvas world.
// The library mounts per visit (cheap, snapshot-driven); the Deep Dive
// dossier mounts on first visit and then stays alive, opacity-swapped, so a
// Canvas ↔ Deep Dive round trip never pays the dossier's full first layout
// and its scroll position survives. A space switch tears it down.
//
// Layout-inert law: the host is wrapped in a GeometryReader window and
// clipped by its mounting site — the dossier's fixed-width columns must
// never propose a size to the canvas ZStack.

import SwiftUI

struct SpaceViewHost<Library: View>: View {
    let thinkspaceId: String?
    let activeView: SpaceView
    let deepDiveChrome: DeepDiveStudyChromeModel
    var contentLeadingInset: CGFloat = 0
    @ViewBuilder let library: () -> Library

    @State private var hasVisitedDeepDive = false
    @State private var homeModel: SpaceHomeModel?

    var body: some View {
        ZStack {
            if activeView == .home, let homeModel, homeModel.spaceID == thinkspaceId {
                SpaceHomeView(model: homeModel)
                    .id(homeModel.spaceID)
                    .padding(.leading, contentLeadingInset)
            }
            if activeView == .library {
                library()
                    .padding(.leading, contentLeadingInset)
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
            if hasVisitedDeepDive {
                SpaceDeepDiveHost(thinkspaceId: thinkspaceId, chrome: deepDiveChrome)
                    .opacity(activeView == .deepDive ? 1 : 0)
                    .allowsHitTesting(activeView == .deepDive)
                    .accessibilityHidden(activeView != .deepDive)
            }
        }
        .background(activeView == .canvas ? Color.clear : DS.bg)
        .onChange(of: activeView, initial: true) { _, view in
            if view == .deepDive { hasVisitedDeepDive = true }
            deepDiveChrome.isFrontmost = (view == .deepDive)
        }
        .onChange(of: thinkspaceId, initial: true) { _, id in
            hasVisitedDeepDive = (activeView == .deepDive)
            // Keep the document model across Home/Library/Canvas visits,
            // without retaining a hidden text editor or its keyboard handlers.
            homeModel = id.map { SpaceHomeModel(spaceID: $0) }
        }
    }
}

/// Resolves the space's Deep Dive profile (one shared in-flight task per
/// space, never minting a second profile) and renders the dossier embedded.
struct SpaceDeepDiveHost: View {
    let thinkspaceId: String?
    let chrome: DeepDiveStudyChromeModel

    @State private var profileAtom: Atom?
    @State private var resolvedFor: String?

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            if let profileAtom {
                DeepDiveOverviewView(
                    atom: profileAtom,
                    presentation: .embeddedInSpace,
                    chrome: chrome,
                    onClose: {}
                )
                .id(profileAtom.uuid)
                .transition(.opacity)
            } else {
                loadingState
            }
        }
        .task(id: thinkspaceId) { await resolve() }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Canvas.thinkspaceChanged)) { _ in
            Task { await resolve() }
        }
    }

    private var loadingState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: SpaceView.deepDive.icon)
                .font(DS.title2)
                .foregroundStyle(DS.textMuted)
            Text("Opening this space's Deep Dive")
                .font(DS.subheadline)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolve() async {
        guard let thinkspaceId else {
            profileAtom = nil
            resolvedFor = nil
            return
        }
        guard resolvedFor != thinkspaceId || profileAtom == nil else { return }
        guard let uuid = await ThinkspaceManager.shared.ensureDeepDiveProfileUUID(for: thinkspaceId),
              let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else {
            return
        }
        guard !Task.isCancelled else { return }
        withAnimation(ProMotionSprings.focusTransition) {
            profileAtom = atom
            resolvedFor = thinkspaceId
        }
    }
}
