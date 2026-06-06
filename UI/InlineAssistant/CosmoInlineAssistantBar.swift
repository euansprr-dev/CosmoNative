import AppKit
import SwiftUI

enum CosmoInlineAssistantBarPresentationPolicy {
    static func isExpanded(
        isHovering: Bool,
        isFocused: Bool,
        hasComposerText: Bool,
        isProcessing: Bool
    ) -> Bool {
        isHovering || isFocused || hasComposerText || isProcessing
    }

    static func shouldBlur(clickPoint: CGPoint, barFrame: CGRect) -> Bool {
        guard barFrame.width > 0, barFrame.height > 0 else { return false }
        return !barFrame.insetBy(dx: -10, dy: -10).contains(clickPoint)
    }
}

private struct CosmoInlineAssistantBarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct CosmoInlineAssistantBarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CosmoInlineAssistantBar: View {
    @ObservedObject var store: CosmoInlineAssistantStore
    let onOpenPane: () -> Void

    @FocusState private var isComposerFocused: Bool
    @State private var isHovering = false
    @State private var isPinnedOpen = false
    @State private var barFrame: CGRect = .zero
    @State private var availableWidth: CGFloat = 0
    @State private var mouseDownMonitor: Any?

    var body: some View {
        morphingBar
            // Hover tracking is bound to the bar's own (rounded) bounds — not the
            // full-width strip below — so only the orb itself reacts to the cursor.
            .contentShape(barShape)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    isPinnedOpen = false
                } else {
                    collapseIfIdle()
                }
            }
            .frame(maxWidth: .infinity)
            .background(widthReader)
            .onPreferenceChange(CosmoInlineAssistantBarWidthPreferenceKey.self) { availableWidth = $0 }
            .onPreferenceChange(CosmoInlineAssistantBarFramePreferenceKey.self) { barFrame = $0 }
            .onChange(of: isComposerFocused) { _, focused in
                guard !focused else { return }
                collapseIfIdle()
            }
            .onAppear { installMouseDownMonitorIfNeeded() }
            .onDisappear { removeMouseDownMonitor() }
            .accessibilityElement(children: .contain)
    }

    // MARK: - Morphing container

    // A single persistent surface that grows from a compact orb into the full
    // composer. The container width animates explicitly (the "bubble"), the
    // background/shadow live behind the clip so the bar reveals as it stretches,
    // and the trailing controls materialise a beat later — the Spotlight feel.
    private var morphingBar: some View {
        barContent
            .frame(width: expandedWidth, alignment: .leading)
            .frame(width: barWidth, alignment: .leading)
            .frame(minHeight: 52)
            .clipShape(barShape)
            .background {
                barShape
                    .fill(DS.surfaceCard.opacity(0.96))
                    .shadow(
                        color: Color.black.opacity(isExpanded ? 0.14 : 0.10),
                        radius: isExpanded ? 22 : 14,
                        x: 0,
                        y: isExpanded ? 10 : 7
                    )
            }
            .background(frameReader)
            .overlay { barShape.stroke(borderColor, lineWidth: 1) }
            .overlay { collapsedTapTarget }
            .animation(morphAnimation, value: isExpanded)
    }

    private var barContent: some View {
        HStack(spacing: 12) {
            iconView
            trailingControls
                .opacity(isExpanded ? 1 : 0)
                .blur(radius: isExpanded ? 0 : 4)
                .scaleEffect(isExpanded ? 1 : 0.92, anchor: .leading)
                .offset(x: isExpanded ? 0 : -10)
                .disabled(!isExpanded)
                .animation(revealAnimation, value: isExpanded)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }

    private var iconView: some View {
        Image(systemName: store.isProcessing ? "sparkles" : "sparkle")
            .font(DS.title2)
            .foregroundStyle(DS.accent)
            .frame(width: 28, height: 28)
            .symbolEffect(.pulse, options: .repeating, value: store.isProcessing)
            .accessibilityHidden(true)
    }

    private var trailingControls: some View {
        HStack(spacing: 12) {
            TextField(promptText, text: $store.composerText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineLimit(1...4)
                .focused($isComposerFocused)
                .onAppear { focusComposerIfPinnedOpen() }
                .onSubmit { submit() }

            if let statusText = store.statusText {
                Text(statusText)
                    .font(DS.subheadline.weight(.medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }

            Button(action: onOpenPane) {
                Image(systemName: "sidebar.right")
                    .font(DS.callout.weight(.medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.textSecondary)
            .help("Open assistant pane")
            .accessibilityLabel("Open assistant pane")

            Button(action: submit) {
                Image(systemName: store.isProcessing ? "stop.fill" : "arrow.up")
                    .font(DS.callout.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(sendFill, in: Circle())
                    .foregroundStyle(sendText)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .help("Send")
            .accessibilityLabel("Send")
        }
    }

    // Invisible hit target that covers the collapsed orb so a click expands and
    // focuses the composer. Removed once expanded so the text field owns clicks.
    @ViewBuilder private var collapsedTapTarget: some View {
        if !isExpanded {
            Button(action: expandAndFocus) {
                barShape.fill(Color.clear).contentShape(barShape)
            }
            .buttonStyle(.plain)
            .help("Open inline assistant")
            .accessibilityLabel("Open inline assistant")
        }
    }

    // MARK: - Geometry readers

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CosmoInlineAssistantBarWidthPreferenceKey.self,
                value: proxy.size.width
            )
        }
    }

    private var frameReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CosmoInlineAssistantBarFramePreferenceKey.self,
                value: proxy.frame(in: .global)
            )
        }
    }

    // MARK: - Derived presentation

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var promptText: String {
        store.isProcessing ? "Working..." : "Describe any change or ask about this workspace"
    }

    private var trimmedComposerText: String {
        store.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedComposerText.isEmpty && !store.isProcessing
    }

    private var isExpanded: Bool {
        isPinnedOpen || CosmoInlineAssistantBarPresentationPolicy.isExpanded(
            isHovering: isHovering,
            isFocused: isComposerFocused,
            hasComposerText: !trimmedComposerText.isEmpty,
            isProcessing: store.isProcessing || store.statusText != nil
        )
    }

    private var collapsedWidth: CGFloat { 56 }

    private var expandedWidth: CGFloat {
        guard availableWidth > 120 else { return 600 }
        return min(availableWidth - 56, 780)
    }

    private var barWidth: CGFloat {
        isExpanded ? expandedWidth : collapsedWidth
    }

    private var sendFill: Color {
        canSubmit ? DS.accent : DS.borderSubtle
    }

    private var sendText: Color {
        canSubmit ? DS.textOnAccent : DS.textMuted
    }

    private var borderColor: Color {
        isComposerFocused ? DS.accent.opacity(0.36) : DS.borderSubtle
    }

    // Bubbly on the way out (slight overshoot), crisp on the way back in.
    private var morphAnimation: Animation {
        isExpanded
            ? .spring(response: 0.42, dampingFraction: 0.68)
            : .spring(response: 0.26, dampingFraction: 0.90)
    }

    // Controls fade in a beat behind the container so the bar reads as "settling
    // into what it is" rather than appearing fully formed.
    private var revealAnimation: Animation {
        isExpanded
            ? .spring(response: 0.34, dampingFraction: 0.82).delay(0.07)
            : .easeOut(duration: 0.12)
    }

    // MARK: - Behavior

    private func submit() {
        guard canSubmit else { return }
        Task { await store.submit() }
    }

    private func expandAndFocus() {
        isPinnedOpen = true
        focusComposerSoon()
    }

    private func focusComposerIfPinnedOpen() {
        guard isPinnedOpen else { return }
        focusComposerSoon()
    }

    private func focusComposerSoon() {
        Task { @MainActor in
            await Task.yield()
            isComposerFocused = true
        }
    }

    private func collapseIfIdle() {
        guard !isComposerFocused, trimmedComposerText.isEmpty, !store.isProcessing else { return }
        isPinnedOpen = false
    }

    private func installMouseDownMonitorIfNeeded() {
        guard mouseDownMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            handleMouseDown(event)
            return event
        }
    }

    private func removeMouseDownMonitor() {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
        self.mouseDownMonitor = nil
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard isComposerFocused || isPinnedOpen else { return }
        guard let window = event.window ?? NSApp.keyWindow else { return }

        let clickPoint = windowTopLeftPoint(for: event, in: window)
        guard CosmoInlineAssistantBarPresentationPolicy.shouldBlur(
            clickPoint: clickPoint,
            barFrame: barFrame
        ) else { return }

        isComposerFocused = false
        isPinnedOpen = false
        window.makeFirstResponder(nil)
    }

    private func windowTopLeftPoint(for event: NSEvent, in window: NSWindow) -> CGPoint {
        let location = event.locationInWindow
        guard let contentView = window.contentView else { return location }
        return CGPoint(x: location.x, y: contentView.bounds.height - location.y)
    }
}
