// CosmoOS/Cosmo/CosmoInputDock.swift
// Global AI input dock - always accessible from anywhere
// Floating, beautiful, Apple-level quality

import SwiftUI
import AppKit

struct CosmoInputDock: View {
    @StateObject private var cosmo = CosmoCore.shared
    @StateObject private var voiceEngine = VoiceEngine.shared
    @State private var inputText = ""
    @State private var isExpanded = false
    @State private var showChat = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Main dock
            HStack(spacing: 12) {
                // Cosmo icon
                Button(action: { withAnimation(.spring()) { showChat.toggle() } }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)

                        Image(systemName: cosmo.isProcessing ? "brain" : "sparkles")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, isActive: cosmo.isProcessing)
                    }
                }
                .buttonStyle(.plain)

                // Input field
                TextField("Ask Cosmo...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFocused)
                    .onSubmit { sendMessage() }
                    .frame(minWidth: 200)

                // Status indicators
                if cosmo.isResearching {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)

                        ProgressView(value: cosmo.researchProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 40)
                    }
                }

                // Voice button (toggles recording)
                Button(action: toggleVoice) {
                    Image(systemName: voiceEngine.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 14))
                        .foregroundColor(voiceEngine.isRecording ? .red : .secondary)
                        .symbolEffect(.pulse, isActive: voiceEngine.isRecording)
                }
                .buttonStyle(.plain)
                .help(voiceEngine.isRecording ? "Stop recording" : "Voice input (or hold Space)")

                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(inputText.isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || cosmo.isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)

            // Quick suggestions
            if isFocused && inputText.isEmpty {
                QuickSuggestions(onSelect: { suggestion in
                    inputText = suggestion
                    sendMessage()
                })
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: isFocused)
        .sheet(isPresented: $showChat) {
            CosmoChatSheet()
        }
    }

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""
        isFocused = false

        Task {
            _ = await cosmo.process(message)
        }
    }

    private func toggleVoice() {
        Task {
            if voiceEngine.isRecording {
                await voiceEngine.stopRecording()
            } else {
                await voiceEngine.startRecording()
            }
        }
    }
}

// MARK: - Quick Suggestions
struct QuickSuggestions: View {
    let onSelect: (String) -> Void

    private let suggestions = [
        "What should I focus on today?",
        "Research trending topics in AI",
        "Create a new idea",
        "Show my recent notes"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: { onSelect(suggestion) }) {
                        Text(suggestion)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .padding(.top, 8)
    }
}

// MARK: - Cosmo Chat Sheet
struct CosmoChatSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chat with Cosmo")
                    .font(.headline)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Chat view
            CosmoChatView()
        }
        .frame(width: 500, height: 600)
    }
}

// MARK: - Global Cosmo Dock Window
class CosmoDockWindowController {
    private var window: KeyablePanel?

    func show() {
        if window == nil {
            createWindow()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    private func createWindow() {
        // Use custom KeyablePanel that can become key (accept text input)
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
            styleMask: [.hudWindow, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.becomesKeyOnlyIfNeeded = false  // Allow becoming key

        // Position at bottom center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 200
            let y = screenFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // SwiftUI content with environment objects
        let cosmoCore = MainActor.assumeIsolated { CosmoCore.shared }
        let hostingView = NSHostingView(
            rootView: CosmoInputDock()
                .environmentObject(cosmoCore)
        )
        panel.contentView = hostingView

        window = panel
    }
}

// MARK: - Custom Panel that can become key (accept text input)
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
