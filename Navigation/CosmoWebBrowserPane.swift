// CosmoOS/Navigation/CosmoWebBrowserPane.swift
// Split-pane WebKit browser for in-app research and reference material.
// Composition root; models, state, and chrome live in Navigation/Browser/.

import SwiftUI
import WebKit
import AppKit

struct CosmoWebBrowserPane: View {
    let paneId: String
    let url: URL
    let title: String?
    let onClose: () -> Void

    @State private var browserState: CosmoWebBrowserState
    @State private var authenticationCoordinator = CosmoBrowserSystemAuthenticationCoordinator()
    @State private var renamingPin: CosmoBrowserPinnedSite?
    @State private var dispatchedCaptureKind: CosmoBrowserResearchCaptureKind?
    @Environment(\.isPaneActive) private var isPaneActive

    init(paneId: String, url: URL, title: String?, onClose: @escaping () -> Void) {
        self.paneId = paneId
        self.url = url
        self.title = title
        self.onClose = onClose
        _browserState = State(initialValue: CosmoWebBrowserState(initialURL: url, title: title, profile: .standard))
    }

    var body: some View {
        VStack(spacing: CosmoSurfaceMetrics.chromeGap) {
            CosmoBrowserToolbarView(browserState: browserState, fallbackURL: url, onClose: onClose)
                .cosmoChromeBandInsets()

            contentWell
                .cosmoInnerWindow()
        }
        .background(DS.bg)
        .task {
            BrowserPaneRegistry.shared.register(browserState, for: paneId)
            await browserState.loadPersistedPins()
        }
        .onDisappear {
            BrowserPaneRegistry.shared.unregister(paneId: paneId)
        }
        .sheet(item: $renamingPin) { pin in
            renameSheet(for: pin)
        }
    }

    // MARK: - Content well

    private var contentWell: some View {
        ZStack(alignment: .top) {
            if browserState.showsStartPage {
                startPage
                    .transition(.opacity)
                    .background(DS.bg)
            } else {
                CosmoBrowserWebView(state: browserState, paneId: paneId)
                    .id(browserState.webViewIdentity)
                    .background(DS.bg)
            }

            if let errorMessage = browserState.errorMessage {
                browserErrorView(errorMessage)
                    .padding(18)
            }

            if case .externalSystemSession(let reason) = browserState.authenticationRoute {
                authenticationNotice(reason: reason)
                    .padding(18)
            }

            if browserState.hasSelection {
                CosmoBrowserCaptureBarView(
                    browserState: browserState,
                    onCapture: dispatchCapture,
                    dispatchedKind: dispatchedCaptureKind
                )
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(ProMotionSprings.focusTransition, value: browserState.showsStartPage)
        .animation(ProMotionSprings.menuAppear, value: browserState.hasSelection)
    }

    private var startPage: some View {
        CosmoBrowserStartPage(
            favorites: browserState.pins,
            recentHistory: browserState.recentHistory,
            onOpen: { url, _ in
                browserState.load(url)
            },
            onOpenInSplit: { url, title in
                openInSplit(url: url, title: title)
            },
            onRename: { pin in
                renamingPin = pin
            },
            onRemove: { pin in
                browserState.unpin(pin)
            }
        )
    }

    /// Open a page beside this pane — routed through the pane router so the
    /// browser cap and pin semantics hold.
    private func openInSplit(url: URL, title: String?) {
        var userInfo: [String: Any] = [
            "url": url,
            "disposition": BrowserOpenDisposition.split.rawValue,
            "sourcePaneId": paneId
        ]
        if let title {
            userInfo["title"] = title
        }
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openWebBrowserPane,
            object: nil,
            userInfo: userInfo
        )
    }

    private func renameSheet(for pin: CosmoBrowserPinnedSite) -> some View {
        CosmoBrowserRenamePinSheet(
            pin: pin,
            onCancel: {
                renamingPin = nil
            },
            onSave: { name in
                Task {
                    await browserState.renamePin(pin.id, to: name)
                }
                renamingPin = nil
            }
        )
    }

    // MARK: - Capture dispatch

    private func dispatchCapture(_ kind: CosmoBrowserResearchCaptureKind) {
        guard dispatchedCaptureKind == nil else { return }
        guard let capture = browserState.makeResearchCapture(kind: kind) else { return }

        switch kind {
        case .quote:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\"\(capture.body)\"\n\(capture.sourceURL.absoluteString)", forType: .string)
        case .research:
            Task {
                _ = try? await AgentToolExecutor.shared.execute(
                    toolName: "capture_research",
                    arguments: [
                        "title": capture.title,
                        "url": capture.sourceURL.absoluteString,
                        "body": capture.body
                    ]
                )
            }
        case .swipe:
            Task {
                _ = try? await AgentToolExecutor.shared.execute(
                    toolName: "capture_swipe",
                    arguments: [
                        "url": capture.sourceURL.absoluteString,
                        "hook": capture.body
                    ]
                )
            }
        case .askCosmo:
            // One Cosmo: route to the assistant pane instead of the old
            // floating chat window.
            CosmoInlineAssistantStore.shared.openPane()
            CosmoInlineAssistantStore.shared.submitPrompt("""
            Analyze this selected passage from \(capture.title):

            \(capture.body)

            Source: \(capture.sourceURL.absoluteString)
            """)
        }

        // Confirmation beat: the pressed chip morphs to a checkmark, then
        // the bar dismisses with the cleared selection.
        withAnimation(ProMotionSprings.snappy) {
            dispatchedCaptureKind = kind
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            browserState.clearSelectedText()
            dispatchedCaptureKind = nil
        }
    }

    // MARK: - Notices

    private func authenticationNotice(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.horizontal")
                    .foregroundStyle(DS.orange)
                Text("Use system browser for this sign-in")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.text)
            }
            Text(reason)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = browserState.currentURL {
                    let didStart = authenticationCoordinator.start(url: url)
                    if !didStart {
                        NSWorkspace.shared.open(url)
                    }
                }
            } label: {
                Label(
                    authenticationCoordinator.isAuthenticating ? "Opening System Sign-In" : "Use System Sign-In",
                    systemImage: "key.horizontal"
                )
                    .font(DS.buttonText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(DS.accent, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(DS.textOnAccent)
            }
            .buttonStyle(.plain)
            Button {
                if let url = browserState.currentURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open Externally", systemImage: "arrow.up.right.square")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: 360, alignment: .leading)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 14)
    }

    private func browserErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(DS.title1)
                .foregroundStyle(DS.orange)
            Text("Could not load this page")
                .font(DS.subheadline)
                .foregroundStyle(DS.text)
            Text(message)
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(action: browserState.reload) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(DS.buttonText)
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(DS.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: 300)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 14)
    }
}
