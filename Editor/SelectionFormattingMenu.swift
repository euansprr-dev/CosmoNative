// CosmoOS/Editor/SelectionFormattingMenu.swift
// Floating menu for formatting text selection
// Dual-mode: formatting (Bold/Italic/etc) ↔ AI (Expand/Condense/Rephrase)
// Animated slide transition between modes.

import SwiftUI

struct SelectionFormattingMenu: View {
    let position: CGPoint
    var compact: Bool = false
    let onDismiss: () -> Void
    var onAIAction: ((AIWritingAction) -> Void)? = nil
    var onCustomPrompt: ((String) -> Void)? = nil

    @State private var mode: MenuMode = .formatting
    @State private var showCustomPrompt = false
    @State private var customPromptText = ""

    private enum MenuMode {
        case formatting, ai
    }

    private var menuHeight: CGFloat { 52 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if mode == .formatting {
                    formattingContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    aiContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(height: menuHeight)
            .background(CosmoColors.softWhite)
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: CosmoColors.glassGrey.opacity(0.3), radius: 10, y: 4)
            .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)

            if showCustomPrompt {
                customPromptField
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .fixedSize()
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: mode)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: showCustomPrompt)
        .position(x: position.x, y: position.y)
    }

    // MARK: - Formatting Mode

    @ViewBuilder
    private var formattingContent: some View {
        FormattingButton(icon: "bold", type: .bold)
        FormattingButton(icon: "italic", type: .italic)
        FormattingButton(icon: "underline", type: .underline)

        if !compact {
            FormattingButton(icon: "strikethrough", type: .strikethrough)

            Divider()
                .frame(height: 20)
                .background(CosmoColors.glassGrey.opacity(0.5))

            FormattingButton(icon: "h1", customLabel: "H1", type: .heading1)
            FormattingButton(icon: "h2", customLabel: "H2", type: .heading2)
            FormattingButton(icon: "h3", customLabel: "H3", type: .heading3)
        }

        Divider()
            .frame(height: 20)
            .background(CosmoColors.glassGrey.opacity(0.5))

        FormattingButton(icon: "list.bullet", type: .bulletList)
        if !compact {
            FormattingButton(icon: "list.number", type: .numberedList)
            FormattingButton(icon: "checklist", type: .checklist)
        }

        // AI sparkle button — gateway to AI mode
        if onAIAction != nil {
            Divider()
                .frame(height: 20)
                .background(CosmoColors.glassGrey.opacity(0.5))

            BarIconButton(icon: "sparkles", tint: DS.accent) {
                mode = .ai
            }
        }
    }

    // MARK: - AI Mode

    @ViewBuilder
    private var aiContent: some View {
        BarIconButton(icon: "chevron.left", tint: CosmoColors.textSecondary) {
            showCustomPrompt = false
            mode = .formatting
        }

        Divider()
            .frame(height: 20)
            .background(CosmoColors.glassGrey.opacity(0.5))

        AIBarButton(icon: "arrow.up.left.and.arrow.down.right", label: "Expand") {
            onAIAction?(.expand)
        }
        AIBarButton(icon: "arrow.down.right.and.arrow.up.left", label: "Condense") {
            onAIAction?(.condense)
        }
        AIBarButton(icon: "arrow.triangle.2.circlepath", label: "Rephrase") {
            onAIAction?(.rephrase)
        }

        if onCustomPrompt != nil {
            Divider()
                .frame(height: 20)
                .background(CosmoColors.glassGrey.opacity(0.5))

            BarIconButton(icon: "ellipsis", tint: CosmoColors.textSecondary) {
                showCustomPrompt.toggle()
            }
        }
    }

    // MARK: - Custom Prompt

    @ViewBuilder
    private var customPromptField: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11))
                .foregroundColor(DS.accent.opacity(0.7))

            TextField("Custom instruction...", text: $customPromptText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.text)
                .onSubmit {
                    submitCustomPrompt()
                }

            Button(action: { submitCustomPrompt() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(DS.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CosmoColors.softWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.accent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
    }

    private func submitCustomPrompt() {
        let text = customPromptText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onCustomPrompt?(text)
        customPromptText = ""
        showCustomPrompt = false
    }
}

// MARK: - Bar Icon Button (circle, icon-only)

private struct BarIconButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isHovered ? tint : tint.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(isHovered ? tint.opacity(0.1) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - AI Bar Button (pill, icon + label)

private struct AIBarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isHovered ? CosmoColors.lavender : CosmoColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? CosmoColors.lavender.opacity(0.08) : CosmoColors.glassGrey.opacity(0.15))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Formatting Button

struct FormattingButton: View {
    let icon: String
    var customLabel: String? = nil
    let type: FormattingType

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            EditorCommandBus.shared.toggleFormatting(type)
        }) {
            ZStack {
                if let label = customLabel {
                    Text(label)
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundColor(isHovered ? CosmoColors.lavender : CosmoColors.textSecondary)
            .frame(width: 32, height: 32)
            .background(
                isHovered ? CosmoColors.lavender.opacity(0.1) : Color.clear
            )
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
