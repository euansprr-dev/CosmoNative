// CosmoOS/Navigation/CosmoWebBrowserPane.swift
// Split-pane WebKit browser for in-app social source review.

import SwiftUI
import WebKit
import AppKit

struct CosmoWebBrowserPane: View {
    let url: URL
    let title: String?
    let onClose: () -> Void

    @StateObject private var browserState: CosmoWebBrowserState
    @Environment(\.isPaneActive) private var isPaneActive

    init(url: URL, title: String?, onClose: @escaping () -> Void) {
        self.url = url
        self.title = title
        self.onClose = onClose
        _browserState = StateObject(wrappedValue: CosmoWebBrowserState(initialURL: url, title: title))
    }

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar

            ZStack(alignment: .top) {
                CosmoBrowserWebView(url: url, state: browserState)
                    .background(DS.bg)

                if browserState.isLoading {
                    ProgressView(value: browserState.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(DS.entitySwipe)
                        .frame(height: 2)
                        .transition(.opacity)
                }

                if let errorMessage = browserState.errorMessage {
                    browserErrorView(errorMessage)
                        .padding(18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(DS.borderSubtle, lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(DS.bg)
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            CosmoBrowserToolbarButton(systemName: "xmark", help: "Close browser", action: onClose)

            Divider()
                .frame(height: 18)
                .overlay(DS.borderSubtle)
                .padding(.horizontal, 2)

            CosmoBrowserToolbarButton(
                systemName: "chevron.left",
                help: "Back",
                isEnabled: browserState.canGoBack,
                action: browserState.goBack
            )
            CosmoBrowserToolbarButton(
                systemName: "chevron.right",
                help: "Forward",
                isEnabled: browserState.canGoForward,
                action: browserState.goForward
            )
            CosmoBrowserToolbarButton(
                systemName: browserState.isLoading ? "xmark.circle" : "arrow.clockwise",
                help: browserState.isLoading ? "Stop loading" : "Reload",
                action: browserState.reloadOrStop
            )

            HStack(spacing: 8) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.entitySwipe)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(browserState.displayTitle)
                        .font(DS.caption)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(browserState.displayURL)
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(DS.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isPaneActive ? DS.entitySwipe.opacity(0.45) : DS.borderSubtle, lineWidth: 1)
            )

            CosmoBrowserToolbarButton(systemName: "safari", help: "Open in external browser") {
                NSWorkspace.shared.open(browserState.currentURL ?? url)
            }
        }
        .padding(10)
    }

    private var sourceIcon: String {
        if (browserState.currentURL ?? url).host?.contains("instagram.com") == true {
            return "camera.fill"
        }
        return "globe"
    }

    private func browserErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .semibold))
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }
}

private struct CosmoBrowserToolbarButton: View {
    let systemName: String
    let help: String
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? DS.textSecondary : DS.textMuted.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered && isEnabled ? DS.surfaceHover : DS.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isHovered && isEnabled ? DS.borderActive : DS.borderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
            if hovering && isEnabled {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

@MainActor
final class CosmoWebBrowserState: ObservableObject {
    @Published var displayTitle: String
    @Published var displayURL: String
    @Published var currentURL: URL?
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?

    private weak var webView: WKWebView?
    private let initialURL: URL

    init(initialURL: URL, title: String?) {
        self.initialURL = initialURL
        self.currentURL = initialURL
        self.displayTitle = title?.isEmpty == false ? title! : Self.fallbackTitle(for: initialURL)
        self.displayURL = Self.displayURLString(for: initialURL)
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        update(from: webView)
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        clearError()
        if webView?.url == nil {
            webView?.load(URLRequest(url: initialURL))
        } else {
            webView?.reload()
        }
    }

    func reloadOrStop() {
        if isLoading {
            webView?.stopLoading()
            update(from: webView)
        } else {
            reload()
        }
    }

    func update(from webView: WKWebView?) {
        guard let webView else { return }
        applySnapshot(
            url: webView.url,
            title: webView.title,
            isLoading: webView.isLoading,
            estimatedProgress: webView.estimatedProgress,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        )
    }

    func applySnapshot(
        url: URL?,
        title: String?,
        isLoading: Bool,
        estimatedProgress: Double,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        let resolvedURL = url ?? currentURL
        setIfChanged(&currentURL, resolvedURL)
        setIfChanged(&displayURL, Self.displayURLString(for: resolvedURL ?? initialURL))
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setIfChanged(&displayTitle, title)
        }
        setIfChanged(&self.isLoading, isLoading)
        setIfChanged(&self.estimatedProgress, estimatedProgress)
        setIfChanged(&self.canGoBack, canGoBack)
        setIfChanged(&self.canGoForward, canGoForward)
    }

    func fail(with error: Error) {
        setIfChanged(&errorMessage, error.localizedDescription)
        update(from: webView)
    }

    func clearError() {
        setIfChanged(&errorMessage, nil)
    }

    private func setIfChanged<Value: Equatable>(_ storage: inout Value, _ newValue: Value) {
        guard storage != newValue else { return }
        storage = newValue
    }

    private static func fallbackTitle(for url: URL) -> String {
        if url.host?.contains("instagram.com") == true {
            return "Instagram"
        }
        return url.host ?? "Web"
    }

    private static func displayURLString(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = nil
        return components?.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? url.absoluteString
    }
}

private struct CosmoBrowserWebView: NSViewRepresentable {
    let url: URL
    @ObservedObject var state: CosmoWebBrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, initialURL: url)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = CosmoBrowserWKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        context.coordinator.webView = webView
        context.coordinator.installDeleteKeyMonitor(for: webView)
        state.attach(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.initialURL != url else { return }
        context.coordinator.initialURL = url
        state.attach(webView)
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: CosmoWebBrowserState
        var initialURL: URL
        weak var webView: WKWebView?
        private var deleteKeyMonitor: Any?

        init(state: CosmoWebBrowserState, initialURL: URL) {
            self.state = state
            self.initialURL = initialURL
        }

        deinit {
            if let deleteKeyMonitor {
                NSEvent.removeMonitor(deleteKeyMonitor)
            }
        }

        func installDeleteKeyMonitor(for webView: WKWebView) {
            if let deleteKeyMonitor {
                NSEvent.removeMonitor(deleteKeyMonitor)
            }

            deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak webView] event in
                guard let webView,
                      Self.isPlainDeleteKey(event),
                      Self.browserOwnsFirstResponder(in: event.window, webView: webView)
                else {
                    return event
                }

                event.window?.firstResponder?.keyDown(with: event)
                return nil
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateState(from: webView, clearError: true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failState(with: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failState(with: error)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" || scheme == "about" else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func updateState(from webView: WKWebView, clearError: Bool = false) {
            let url = webView.url
            let title = webView.title
            let isLoading = webView.isLoading
            let estimatedProgress = webView.estimatedProgress
            let canGoBack = webView.canGoBack
            let canGoForward = webView.canGoForward

            Task { @MainActor in
                if clearError {
                    state.clearError()
                }
                state.applySnapshot(
                    url: url,
                    title: title,
                    isLoading: isLoading,
                    estimatedProgress: estimatedProgress,
                    canGoBack: canGoBack,
                    canGoForward: canGoForward
                )
            }
        }

        private func failState(with error: Error) {
            let message = error.localizedDescription
            Task { @MainActor in
                state.fail(with: NSError(domain: "CosmoWebBrowserPane", code: 0, userInfo: [NSLocalizedDescriptionKey: message]))
            }
        }

        private static func isPlainDeleteKey(_ event: NSEvent) -> Bool {
            guard event.keyCode == 51 || event.keyCode == 117 else { return false }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return !modifiers.contains(.command) && !modifiers.contains(.control)
        }

        private static func browserOwnsFirstResponder(in window: NSWindow?, webView: WKWebView) -> Bool {
            guard let responder = window?.firstResponder else { return false }

            if responder === webView {
                return true
            }

            if let responderView = responder as? NSView {
                return responderView === webView || responderView.isDescendant(of: webView)
            }

            return String(describing: type(of: responder)).contains("WK")
        }
    }
}

private final class CosmoBrowserWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
