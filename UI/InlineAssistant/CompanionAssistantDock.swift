import AppKit
import SwiftUI

extension CosmoInlineAssistantPhase {
    var companionExpression: CompanionExpression {
        switch self {
        case .idle: return .resting
        case .planning, .gathering: return .working
        case .drafting: return .speaking
        case .reviewing: return .reviewing
        }
    }
}

/// A narrow observer: typing and streaming never invalidate the workspace shell.
struct CompanionAssistantDock: View {
    let panes: PaneManager
    var isSuppressed: Bool
    private var coordinator: CompanionAssistantCoordinator { .shared }
    private var companion: CompanionStore { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CosmoInlineAssistantPhase = .idle
    @State private var showWorld = false
    @State private var isHovered = false
    @State private var windowNumber: Int?

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .trailing, spacing: DS.space8) {
                GlobalStatusPill()
                if !isSuppressed && (coordinator.host != .pane || !coordinator.isOwner(windowNumber: windowNumber) || !isAssistantPaneVisible) {
                    dock(in: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(DS.space16)
        }
        .onReceive(CosmoInlineAssistantStore.shared.$phase.removeDuplicates()) { phase = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            CosmoInlineAssistantStore.shared.savePresentationDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            CosmoInlineAssistantStore.shared.savePresentationDraft()
        }
        .onReceive(CosmoInlineAssistantStore.shared.$isProcessing.removeDuplicates()) { if $0 { coordinator.runBegan() } }
        .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Navigation.attachInlineAssistantContext)) { attach($0) }
        .background(AssistantWindowReader { window in
            windowNumber = window?.windowNumber
            coordinator.register(window: window, panes: panes)
            coordinator.reconcilePane(isOpen: hasAssistantPane, windowNumber: windowNumber)
        })
        .onChange(of: hasAssistantPane) { _, open in coordinator.reconcilePane(isOpen: open, windowNumber: windowNumber) }
        .onChange(of: isSuppressed) { _, suppressed in if suppressed { CompanionDockMetrics.shared.footprint = .zero } }
        .sheet(isPresented: $showWorld) { CompanionPickerPopover() }
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: coordinator.host)
    }

    @ViewBuilder private func dock(in size: CGSize) -> some View {
        if coordinator.host == .compact && coordinator.isOwner(windowNumber: windowNumber) {
            CompanionQuickChatHost(onExpand: { coordinator.openPane(using: panes, userInitiated: true) }, onWorld: { showWorld = true })
                .frame(width: CompanionAssistantPlacement.compactSize(in: size).width,
                       height: CompanionAssistantPlacement.compactSize(in: size).height)
                .transition(.scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
        } else if coordinator.showsEntrance {
            VStack(alignment: .trailing, spacing: DS.space8) {
                if companion.moment != nil { CompanionMomentBanner().frame(maxWidth: min(360, size.width - 32)) }
                launcher
            }
        }
    }

    private var launcher: some View {
        Button {
            if hasAssistantPane || coordinator.prefersPane { coordinator.openPane(using: panes, userInitiated: true) }
            else { coordinator.openCompact(panes: panes) }
        } label: {
            VStack(spacing: 0) {
                if coordinator.showsCharacter {
                    CompanionCharacterView(companion: companion.companion, growth: companion.growth,
                        expression: companion.moment != nil ? .celebrating : isHovered && phase == .idle ? .attentive : phase.companionExpression,
                        size: 76, quiet: coordinator.quietMotion)
                } else {
                    Image(systemName: "sparkles").font(DS.title2).foregroundStyle(DS.accent)
                        .frame(width: 52, height: 52)
                        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 26)
                }
                if phase.isWorking || phase == .reviewing {
                    Text(phase == .reviewing ? "Ready to review" : "Working")
                        .font(DS.caption2).foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.space8).padding(.vertical, DS.space4)
                        .background(DS.bg, in: Capsule())
                }
            }
            .frame(minWidth: 64, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(CompanionPressStyle())
        .onHover { isHovered = $0 }
        .help("Chat with Cosmo · Open as a pane with ⌥A")
        .accessibilityLabel("Open Cosmo assistant, \(companion.companion.name)")
        .contextMenu {
            Button("Open as a pane", systemImage: "rectangle.split.2x1") { coordinator.openPane(using: panes, userInitiated: true) }
            Button("Life with \(companion.companion.name)", systemImage: "leaf") { showWorld = true }
            Divider()
            Toggle("Show companion", isOn: Binding(get: { coordinator.showsCharacter }, set: { coordinator.showsCharacter = $0 }))
            Toggle("Quiet movement", isOn: Binding(get: { coordinator.quietMotion }, set: { coordinator.quietMotion = $0 }))
            Toggle("Open directly as a pane", isOn: Binding(get: { coordinator.prefersPane }, set: { coordinator.prefersPane = $0 }))
            Divider()
            Button("Hide entrance · use ⌥A") { coordinator.showsEntrance = false }
        }
        .id(coordinator.appearanceRevision)
        // The corner's neighbours (canvas zoom controls, panel tails) keep
        // clear of this footprint. The quick chat replaces the launcher in
        // place, so the reservation holds while it is open.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { CompanionDockMetrics.shared.footprint = $0 }
        .onDisappear { if coordinator.host != .compact { CompanionDockMetrics.shared.footprint = .zero } }
    }

    private var hasAssistantPane: Bool {
        panes.panes.contains { $0.id == PaneContent.inlineAssistant.id || $0.id == PaneContent.cosmoWindow.id }
    }
    private var isAssistantPaneVisible: Bool {
        [panes.focusedPaneId, panes.pinnedPaneId].contains { $0 == PaneContent.inlineAssistant.id || $0 == PaneContent.cosmoWindow.id }
    }

    private func attach(_ notification: Notification) {
        guard let uuid = notification.userInfo?["atomUuid"] as? String, !uuid.isEmpty else { return }
        if hasAssistantPane { coordinator.openPane(using: panes, userInitiated: true) }
        else { coordinator.openCompact(panes: panes) }
        Task { @MainActor in
            let store = CosmoInlineAssistantStore.shared
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
            guard !store.selectedContextAtoms.contains(where: { $0.uuid == uuid }) else { return }
            let insertion = store.insertContextMention(atom, selection: store.composerSelection)
            store.composerText = insertion.text
            store.composerSelection = insertion.selection
        }
    }
}

struct CompanionQuickChatHost: View {
    let onExpand: () -> Void
    let onWorld: () -> Void
    private var coordinator: CompanionAssistantCoordinator { .shared }

    var body: some View {
        VStack(spacing: 0) {
            CompanionQuickChatHeader(onExpand: onExpand, onWorld: onWorld)
            AssistantConversationSurface(store: .shared)
                .clipShape(.rect(cornerRadius: 16))
                .padding([.horizontal, .bottom], DS.space8)
        }
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 24)
        .background(AssistantOutsideClickMonitor { coordinator.dismiss() })
        .background {
            Button("") { coordinator.dismiss() }
                .keyboardShortcut(.escape, modifiers: []).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }
}

private struct CompanionQuickChatHeader: View {
    let onExpand: () -> Void
    let onWorld: () -> Void
    var body: some View {
        HStack(spacing: DS.space8) {
            CompanionAssistantIdentity(onWorld: onWorld)
            Spacer(minLength: 0)
            Button(action: onExpand) {
                Image(systemName: "rectangle.split.2x1").font(DS.callout).frame(width: 44, height: 44)
            }.buttonStyle(CompanionPressStyle()).help("Open this conversation as a pane (⌥A)").accessibilityLabel("Open as a pane")
            Button { CompanionAssistantCoordinator.shared.dismiss() } label: {
                Image(systemName: "xmark").font(DS.callout).frame(width: 44, height: 44)
            }.buttonStyle(CompanionPressStyle()).help("Close chat (Esc); your draft stays").accessibilityLabel("Close chat")
        }
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, DS.space12).padding(.vertical, DS.space4)
    }
}

/// Shares only phase changes with the engine, not its composer or token stream.
struct CompanionAssistantIdentity: View {
    var onWorld: () -> Void
    @State private var phase: CosmoInlineAssistantPhase = .idle
    private var companion: CompanionStore { .shared }
    var body: some View {
        Button(action: onWorld) {
            HStack(spacing: DS.space4) {
                CompanionCharacterView(companion: companion.companion, growth: companion.growth,
                    expression: phase.companionExpression, size: 44, quiet: CompanionAssistantCoordinator.shared.quietMotion)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cosmo").font(DS.headline).foregroundStyle(DS.text)
                    Text("With \(companion.companion.name)").font(DS.caption2).foregroundStyle(DS.textMuted)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(CompanionPressStyle()).help("Explore your companion").accessibilityLabel("Cosmo with \(companion.companion.name). Companion settings")
        .onReceive(CosmoInlineAssistantStore.shared.$phase.removeDuplicates()) { phase = $0 }
    }
}

private struct AssistantOutsideClickMonitor: NSViewRepresentable {
    let dismiss: () -> Void
    func makeNSView(context: Context) -> MonitorView { let view = MonitorView(); view.dismiss = dismiss; return view }
    func updateNSView(_ view: MonitorView, context: Context) { view.dismiss = dismiss }
    final class MonitorView: NSView {
        var dismiss: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      window.isKeyWindow, NSApp.modalWindow == nil,
                      !CosmoInlineAssistantStore.shared.composerHasOpenMenu,
                      !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.dismiss?()
                return event // The workspace still receives the original click.
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
