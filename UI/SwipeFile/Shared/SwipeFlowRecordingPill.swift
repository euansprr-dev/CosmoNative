// CosmoOS/UI/SwipeFile/Shared/SwipeFlowRecordingPill.swift
// The flow-recording pill: one component, three homes (the browser pane
// toolbar, the ⌥C overlay header, the Swipe Home masthead).
//
// It exists to answer one question at a glance — "is what I'm about to swipe
// going to land in the funnel?" — everywhere a capture can start. A recording
// mode you can forget you are in is a recording mode that ruins a library, so
// the pill is present on every surface that can capture, not just the one you
// started it from.

import SwiftUI

struct SwipeFlowRecordingPill: View {
    /// `.compact` drops the label to a step count — for the browser toolbar,
    /// where the address field owns the width.
    enum Size { case regular, compact }

    var size: Size = .regular

    @State private var recorder = SwipeFlowRecorder.shared
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let session = recorder.session {
            content(session)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                .animation(reduceMotion ? .none : ProMotionSprings.bouncy, value: session)
        }
    }

    private func content(_ session: SwipeFlowRecorder.Session) -> some View {
        HStack(spacing: DS.space6) {
            // A soft dot, not a red blink: this records what you deliberately
            // swipe, not the screen. Alarm chrome would misdescribe it.
            Circle()
                .fill(DS.accent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(size == .compact ? stepLabel(session) : session.pillLabel)
                .font(DS.caption.weight(.medium))
                .foregroundStyle(DS.text)
                .lineLimit(1)
                .contentTransition(.numericText())

            Button {
                withAnimation(ProMotionSprings.gentle) { recorder.stop() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(DS.caption2.weight(.semibold))
                    .foregroundStyle(isHovered ? DS.text : DS.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop recording — the funnel keeps every step it has")
            .accessibilityLabel("Stop recording flow")
        }
        .padding(.leading, DS.space10)
        .padding(.trailing, 2)
        .frame(height: 26)
        .glassEffect(.regular, in: .capsule)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .help("Recording into \(session.name) — every swipe becomes the next step")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording into \(session.pillLabel)")
    }

    private func stepLabel(_ session: SwipeFlowRecorder.Session) -> String {
        "\(session.stepCount)"
    }
}

// MARK: - Start control

/// "Record a funnel" — the entry point that turns the pill on. Lives beside
/// the pill on surfaces where starting makes sense (Swipe Home, the browser
/// pane's overflow menu).
struct SwipeFlowRecordButton: View {
    @State private var recorder = SwipeFlowRecorder.shared
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        if !recorder.isRecording {
            Button {
                name = SwipeFlowRecorder.defaultName()
                isNaming = true
            } label: {
                Label("Record a funnel", systemImage: SwipeKind.flow.iconName)
            }
            .popover(isPresented: $isNaming, arrowEdge: .bottom) {
                namingPopover
            }
        }
    }

    /// A prefilled name and one Return — starting must cost one click, or the
    /// recorder is something you use once and never again.
    private var namingPopover: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            Text("Name this funnel")
                .font(DS.subheadline.weight(.semibold))
                .foregroundStyle(DS.text)

            TextField("Funnel name", text: $name)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .padding(.horizontal, DS.space10)
                .frame(height: 30)
                .dsGlassInput(isFocused: true, cornerRadius: 8)
                .onSubmit { start() }

            HStack {
                Spacer()
                Button("Start") { start() }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.space16)
        .frame(width: 280)
    }

    private func start() {
        let chosen = name
        isNaming = false
        Task { await recorder.start(named: chosen) }
    }
}
