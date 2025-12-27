// CosmoOS/Editor/EditorToolbar.swift
// Apple Notes-style formatting toolbar

import SwiftUI
import AppKit

struct EditorToolbar: View {
    @Binding var attributedText: NSAttributedString
    @Binding var cursorPosition: Int

    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var isStrikethrough = false
    @State private var currentFontSize: CGFloat = 16
    @State private var showColorPicker = false
    @State private var selectedColor: Color = .primary

    var body: some View {
        HStack(spacing: 2) {
            // Text style group
            Group {
                ToolbarButton(icon: "bold", isActive: isBold, tooltip: "Bold (⌘B)") {
                    toggleBold()
                }

                ToolbarButton(icon: "italic", isActive: isItalic, tooltip: "Italic (⌘I)") {
                    toggleItalic()
                }

                ToolbarButton(icon: "underline", isActive: isUnderline, tooltip: "Underline (⌘U)") {
                    toggleUnderline()
                }

                ToolbarButton(icon: "strikethrough", isActive: isStrikethrough, tooltip: "Strikethrough") {
                    toggleStrikethrough()
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Headers
            Group {
                Menu {
                    Button("Normal Text") { setFontSize(16) }
                    Button("Heading 1") { setFontSize(28) }
                    Button("Heading 2") { setFontSize(22) }
                    Button("Heading 3") { setFontSize(18) }
                    Button("Small") { setFontSize(13) }
                } label: {
                    HStack(spacing: 4) {
                        Text("Aa")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Lists
            Group {
                ToolbarButton(icon: "list.bullet", isActive: false, tooltip: "Bullet List") {
                    insertBulletList()
                }

                ToolbarButton(icon: "list.number", isActive: false, tooltip: "Numbered List") {
                    insertNumberedList()
                }

                ToolbarButton(icon: "checklist", isActive: false, tooltip: "Checklist") {
                    insertChecklist()
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Alignment
            Group {
                ToolbarButton(icon: "text.alignleft", isActive: false, tooltip: "Align Left") {
                    setAlignment(.left)
                }

                ToolbarButton(icon: "text.aligncenter", isActive: false, tooltip: "Align Center") {
                    setAlignment(.center)
                }

                ToolbarButton(icon: "text.alignright", isActive: false, tooltip: "Align Right") {
                    setAlignment(.right)
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Extras
            Group {
                ToolbarButton(icon: "link", isActive: false, tooltip: "Insert Link") {
                    insertLink()
                }

                ToolbarButton(icon: "photo", isActive: false, tooltip: "Insert Image") {
                    insertImage()
                }

                ColorPicker("", selection: $selectedColor)
                    .labelsHidden()
                    .frame(width: 24, height: 24)
                    .help("Text Color")
                    .onChange(of: selectedColor) { _, newColor in
                        setTextColor(newColor)
                    }
            }

            Spacer()

            // AI assist
            Button {
                aiAssist()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("AI")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("AI Writing Assistant")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Text Formatting Actions
    private func toggleBold() {
        isBold.toggle()
        applyFontTrait(isBold ? .boldFontMask : [], remove: isBold ? [] : .boldFontMask)
    }

    private func toggleItalic() {
        isItalic.toggle()
        applyFontTrait(isItalic ? .italicFontMask : [], remove: isItalic ? [] : .italicFontMask)
    }

    private func toggleUnderline() {
        isUnderline.toggle()
        applyAttribute(.underlineStyle, value: isUnderline ? NSUnderlineStyle.single.rawValue : 0)
    }

    private func toggleStrikethrough() {
        isStrikethrough.toggle()
        applyAttribute(.strikethroughStyle, value: isStrikethrough ? NSUnderlineStyle.single.rawValue : 0)
    }

    private func setFontSize(_ size: CGFloat) {
        currentFontSize = size
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let range = NSRange(location: 0, length: mutableText.length)

        mutableText.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            if let font = value as? NSFont {
                let newFont = NSFont(descriptor: font.fontDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
                mutableText.addAttribute(.font, value: newFont, range: attrRange)
            }
        }

        attributedText = mutableText
    }

    private func applyFontTrait(_ traits: NSFontTraitMask, remove: NSFontTraitMask) {
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let range = NSRange(location: 0, length: mutableText.length)

        mutableText.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            if let font = value as? NSFont {
                var newFont = font

                if !traits.isEmpty {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: traits)
                }

                if !remove.isEmpty {
                    newFont = NSFontManager.shared.convert(newFont, toNotHaveTrait: remove)
                }

                mutableText.addAttribute(.font, value: newFont, range: attrRange)
            }
        }

        attributedText = mutableText
    }

    private func applyAttribute(_ key: NSAttributedString.Key, value: Any) {
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let range = NSRange(location: 0, length: mutableText.length)
        mutableText.addAttribute(key, value: value, range: range)
        attributedText = mutableText
    }

    private func setAlignment(_ alignment: NSTextAlignment) {
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let range = NSRange(location: 0, length: mutableText.length)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment

        mutableText.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        attributedText = mutableText
    }

    private func setTextColor(_ color: Color) {
        let nsColor = NSColor(color)
        applyAttribute(.foregroundColor, value: nsColor)
    }

    private func insertBulletList() {
        insertAtCursor("• ")
    }

    private func insertNumberedList() {
        insertAtCursor("1. ")
    }

    private func insertChecklist() {
        insertAtCursor("☐ ")
    }

    private func insertLink() {
        // TODO: Show link insertion dialog
        insertAtCursor("[Link](url)")
    }

    private func insertImage() {
        // TODO: Show image picker
        print("🖼️ Insert image...")
    }

    private func insertAtCursor(_ text: String) {
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let insertionPoint = min(cursorPosition, mutableText.length)

        let insertString = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: currentFontSize)]
        )

        mutableText.insert(insertString, at: insertionPoint)
        attributedText = mutableText
    }

    private func aiAssist() {
        print("🧠 AI Writing Assistant activated...")
        // TODO: Show AI assistant overlay
    }
}

// MARK: - Toolbar Button
struct ToolbarButton: View {
    let icon: String
    let isActive: Bool
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .accentColor : .primary)
                .frame(width: 28, height: 28)
                .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
