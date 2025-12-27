// CosmoOS/Navigation/CommandHub/Components/HubSearchBar.swift
// Premium Search Bar with Voice Toggle
// Voice-first, text-second - the Cosmo way

import SwiftUI
import AppKit

// MARK: - Hub Search Bar
struct HubSearchBar: View {
    @Binding var query: String
    let isListening: Bool
    let onVoiceToggle: () -> Void
    let onSubmit: () -> Void
    let onPaste: (String) -> Void

    @State private var isHovered = false
    @State private var isFocused = false
    @State private var shouldFocusField = false

    var body: some View {
        HStack(spacing: 12) {
            // Voice mic button (primary action - voice-first)
            VoiceMicButton(
                isListening: isListening,
                onTap: onVoiceToggle
            )

            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isFocused ? CosmoColors.lavender : CosmoColors.textTertiary)

                PasteAwareTextField(
                    placeholder: "Search, create, or ask Cosmo...",
                    text: $query,
                    shouldFocus: $shouldFocusField,
                    onSubmit: onSubmit,
                    onPaste: onPaste
                )

                // Clear button
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(searchFieldBackground)
            .overlay(searchFieldBorder)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .animation(.easeOut(duration: 0.15), value: query.isEmpty)
        }
        .onAppear {
            isFocused = true
            shouldFocusField = true
        }
    }

    // MARK: - Background
    private var searchFieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                isFocused
                    ? Color.white
                    : CosmoColors.softWhite.opacity(0.8)
            )
    }

    // MARK: - Border
    private var searchFieldBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                isFocused
                    ? CosmoColors.lavender.opacity(0.5)
                    : CosmoColors.glassGrey.opacity(0.5),
                lineWidth: isFocused ? 2 : 1
            )
            // Focus glow
            .shadow(
                color: isFocused ? CosmoColors.lavender.opacity(0.2) : Color.clear,
                radius: 8,
                y: 0
            )
    }
}

// MARK: - Paste-aware Text Field (macOS)
/// SwiftUI `TextField` doesn’t expose paste events, so we wrap an `NSTextField` to detect paste.
struct PasteAwareTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var shouldFocus: Bool
    let onSubmit: () -> Void
    let onPaste: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            shouldFocus: $shouldFocus,
            onSubmit: onSubmit,
            onPaste: onPaste
        )
    }

    func makeNSView(context: Context) -> PasteDetectingNSTextField {
        let field = PasteDetectingNSTextField()
        field.delegate = context.coordinator
        field.pasteDelegate = context.coordinator

        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: 15, weight: .regular)
        field.textColor = NSColor(CosmoColors.textPrimary)

        return field
    }

    func updateNSView(_ nsView: PasteDetectingNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if shouldFocus, let window = nsView.window, window.firstResponder !== nsView.currentEditor() {
            window.makeFirstResponder(nsView)
            // One-shot focus request.
            DispatchQueue.main.async {
                shouldFocus = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, PasteDetectingNSTextFieldDelegate {
        @Binding var text: String
        @Binding var shouldFocus: Bool
        let onSubmit: () -> Void
        let onPaste: (String) -> Void

        init(
            text: Binding<String>,
            shouldFocus: Binding<Bool>,
            onSubmit: @escaping () -> Void,
            onPaste: @escaping (String) -> Void
        ) {
            _text = text
            _shouldFocus = shouldFocus
            self.onSubmit = onSubmit
            self.onPaste = onPaste
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }

        func textFieldDidPaste(_ pastedString: String) {
            onPaste(pastedString)
        }
    }
}

protocol PasteDetectingNSTextFieldDelegate: AnyObject {
    func textFieldDidPaste(_ pastedString: String)
}

final class PasteDetectingNSTextField: NSTextField {
    weak var pasteDelegate: PasteDetectingNSTextFieldDelegate?

    /// `NSTextField` doesn’t expose a `paste(_:)` override point. Intercept ⌘V via key equivalents.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "v" {
            let pasted = NSPasteboard.general.string(forType: .string) ?? ""

            // Let AppKit perform the paste into the field editor.
            let handledBySuper = super.performKeyEquivalent(with: event)
            if !handledBySuper {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            }

            pasteDelegate?.textFieldDidPaste(pasted)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Voice Mic Button
struct VoiceMicButton: View {
    let isListening: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0

    private let buttonSize: CGFloat = 44

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer pulse ring (when listening)
                if isListening {
                    Circle()
                        .stroke(CosmoColors.emerald.opacity(0.3), lineWidth: 2)
                        .frame(width: buttonSize + 12, height: buttonSize + 12)
                        .scaleEffect(pulseScale)
                        .opacity(2 - pulseScale)
                }

                // Background
                Circle()
                    .fill(buttonBackground)
                    .frame(width: buttonSize, height: buttonSize)

                // Border
                Circle()
                    .stroke(buttonBorderColor, lineWidth: 1.5)
                    .frame(width: buttonSize, height: buttonSize)

                // Mic icon
                Image(systemName: isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
                    .symbolEffect(.bounce, value: isListening)
            }
            .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
            .shadow(
                color: isListening ? CosmoColors.emerald.opacity(0.3) : (isHovered ? CosmoColors.lavender.opacity(0.2) : Color.clear),
                radius: isListening ? 12 : 8,
                y: 0
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(HubSprings.hover) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(HubSprings.press) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(HubSprings.press) {
                        isPressed = false
                    }
                }
        )
        .onAppear {
            if isListening {
                startPulse()
            }
        }
        .onChange(of: isListening) { _, newValue in
            if newValue {
                startPulse()
            }
        }
    }

    // MARK: - Colors
    private var buttonBackground: some ShapeStyle {
        if isListening {
            return AnyShapeStyle(CosmoColors.emerald.opacity(0.15))
        } else if isHovered {
            return AnyShapeStyle(CosmoColors.lavender.opacity(0.1))
        } else {
            return AnyShapeStyle(Color.white.opacity(0.9))
        }
    }

    private var buttonBorderColor: Color {
        if isListening {
            return CosmoColors.emerald.opacity(0.6)
        } else if isHovered {
            return CosmoColors.lavender.opacity(0.5)
        } else {
            return CosmoColors.glassGrey.opacity(0.5)
        }
    }

    private var iconColor: Color {
        if isListening {
            return CosmoColors.emerald
        } else if isHovered {
            return CosmoColors.lavender
        } else {
            return CosmoColors.textSecondary
        }
    }

    // MARK: - Pulse Animation
    private func startPulse() {
        pulseScale = 1.0
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
            pulseScale = 1.5
        }
    }
}

// MARK: - Search Suggestions
struct SearchSuggestions: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                SuggestionChip(
                    text: suggestion,
                    onTap: { onSelect(suggestion) }
                )
            }
        }
    }
}

// MARK: - Suggestion Chip
struct SuggestionChip: View {
    let text: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? CosmoColors.lavender : CosmoColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isHovered ? CosmoColors.lavender.opacity(0.1) : CosmoColors.glassGrey.opacity(0.3))
                )
                .overlay(
                    Capsule()
                        .stroke(isHovered ? CosmoColors.lavender.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct HubSearchBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            // Normal state
            HubSearchBar(
                query: .constant(""),
                isListening: false,
                onVoiceToggle: {},
                onSubmit: {},
                onPaste: { _ in }
            )

            // With query
            HubSearchBar(
                query: .constant("marketing ideas"),
                isListening: false,
                onVoiceToggle: {},
                onSubmit: {},
                onPaste: { _ in }
            )

            // Listening state
            HubSearchBar(
                query: .constant(""),
                isListening: true,
                onVoiceToggle: {},
                onSubmit: {},
                onPaste: { _ in }
            )

            // Suggestions
            SearchSuggestions(
                suggestions: ["New idea", "Open calendar", "Show tasks"],
                onSelect: { _ in }
            )
        }
        .padding(40)
        .background(CosmoColors.softWhite)
        .frame(width: 600, height: 400)
    }
}
#endif
