// CosmoOS/Editor/SelectionFormattingMenu.swift
// Floating menu for formatting text selection
// Appears above the selected text with "Apple Buzz-its" / Cosmic Glass styling.

import SwiftUI

struct SelectionFormattingMenu: View {
    let position: CGPoint
    var compact: Bool = false  // Compact mode for notes
    let onDismiss: () -> Void

    // Constants for menu dimensions
    private var menuWidth: CGFloat { compact ? 180 : 260 }
    private var menuHeight: CGFloat { 44 }

    var body: some View {
        HStack(spacing: 4) {
            FormattingButton(icon: "bold", type: .bold)
            FormattingButton(icon: "italic", type: .italic)
            
            if !compact {
                FormattingButton(icon: "strikethrough", type: .strikethrough)
                
                Divider()
                    .frame(height: 20)
                    .background(CosmoColors.glassGrey.opacity(0.5))

                FormattingButton(icon: "h1", customLabel: "H1", type: .heading1)
                FormattingButton(icon: "h2", customLabel: "H2", type: .heading2)
            }

            Divider()
                .frame(height: 20)
                .background(CosmoColors.glassGrey.opacity(0.5))

            FormattingButton(icon: "list.bullet", type: .bulletList)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: menuWidth, height: menuHeight)
        .background(CosmoColors.softWhite)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: CosmoColors.glassGrey.opacity(0.3), radius: 10, y: 4)
        .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
        // Adjust position to center formatting bar above selection
        .position(x: position.x + (menuWidth / 2) - (compact ? 90 : 130), y: position.y - menuHeight - 12) 
        // Logic: position passed is the top-left of the selection rect. 
        // We want to center the menu horizontally relative to selection (or just above it).
        // For simplicity, we align left or try to center if we had selection width.
        // Assuming position is the top-left corner of geometry-clamped selection.
        .onAppear {
            // Optional: Animation or focus handling
        }
    }
}

// MARK: - Formatting Button
struct FormattingButton: View {
    let icon: String // SF Symbol name
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
