// CosmoOS/Editor/RichTextEditor.swift
// Apple Notes-quality rich text editor with TextKit 2
// Slash commands, @mentions, markdown, inline embeds
// Premium overlay behavior: dismiss on outside click, scroll, focus loss

import SwiftUI
import AppKit

struct RichTextEditor: View {
    @Binding var text: NSAttributedString
    @Binding var plainText: String

    @State private var showSlashMenu = false
    @State private var showMentionMenu = false
    @State private var showSelectionMenu = false
    @State private var slashMenuPosition: CGPoint = .zero
    @State private var mentionMenuPosition: CGPoint = .zero
    @State private var selectionMenuPosition: CGPoint = .zero
    @State private var mentionSearchQuery = ""
    @State private var cursorPosition: Int = 0
    @State private var shouldRefocusEditor = false
    
    // Configuration
    var fontSize: CGFloat = 16
    var compact: Bool = false  // Compact mode for notes
    var darkMode: Bool = false  // Dark mode for Thinkspace blocks

    // Geometry for menu clamping
    @State private var containerSize: CGSize = .zero
    @State private var outsideClickDismissMonitor: Any?

    @EnvironmentObject var voiceEngine: VoiceEngine

    let placeholder: String
    let onSave: ((NSAttributedString) -> Void)?

    /// Whether any overlay menu is currently visible
    private var isOverlayVisible: Bool {
        showSlashMenu || showMentionMenu || showSelectionMenu
    }

    init(
        text: Binding<NSAttributedString>,
        plainText: Binding<String>,
        fontSize: CGFloat = 16,
        compact: Bool = false,
        placeholder: String = "Start typing...",
        darkMode: Bool = false,
        onSave: ((NSAttributedString) -> Void)? = nil
    ) {
        self._text = text
        self._plainText = plainText
        self.fontSize = fontSize
        self.compact = compact
        self.placeholder = placeholder
        self.darkMode = darkMode
        self.onSave = onSave
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Main editor
                TextKitEditorRepresentable(
                    attributedText: $text,
                    plainText: $plainText,
                    cursorPosition: $cursorPosition,
                    shouldRefocus: $shouldRefocusEditor,
                    fontSize: fontSize,
                    darkMode: darkMode,
                    onSlashCommand: { position in
                        // Disable slash commands in compact mode
                        if !compact {
                            slashMenuPosition = clampMenuPosition(position, menuSize: CGSize(width: 280, height: 340), in: geometry.size)
                            showSlashMenu = true
                        }
                    },
                    onMention: { position, query in
                        // Disable mentions in compact mode
                        if !compact {
                            mentionMenuPosition = clampMenuPosition(position, menuSize: CGSize(width: 300, height: 290), in: geometry.size)
                            mentionSearchQuery = query
                            showMentionMenu = true
                        }
                    },
                    onSelectionChange: { range, position in
                        if range.length > 0 {
                            // Don't show if other menus are active
                            if !showSlashMenu && !showMentionMenu {
                                // Use compact menu size in compact mode
                                let menuSize = compact ? CGSize(width: 180, height: 48) : CGSize(width: 260, height: 60)
                                selectionMenuPosition = clampMenuPosition(position, menuSize: menuSize, in: geometry.size)
                                showSelectionMenu = true
                            }
                        } else {
                            DispatchQueue.main.async {
                                showSelectionMenu = false
                            }
                        }
                    },
                    onDismissMenus: {
                        dismissAllOverlays()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Ensure the entire editor area is clickable, even when empty
                .contentShape(Rectangle())

                // Placeholder - aligned with textContainerInset (16x16)
                if plainText.isEmpty {
                    Text(placeholder)
                        .foregroundColor(darkMode ? Color.white.opacity(0.4) : CosmoColors.textTertiary)
                        .padding(.top, 16)  // Match textContainerInset height
                        .padding(.leading, 16)  // Match textContainerInset width
                        .allowsHitTesting(false)

                    // Clickable overlay to focus empty editor
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            shouldRefocusEditor = true
                        }
                }

                // MARK: - Invisible dismiss layer (captures outside clicks)
                if isOverlayVisible {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            dismissAllOverlays()
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { _ in
                                    // Scroll/drag detected – dismiss
                                    dismissAllOverlays()
                                }
                        )
                        .allowsHitTesting(true)
                }

                // Slash command menu
                if showSlashMenu {
                    SlashCommandMenu(
                        position: slashMenuPosition,
                        onSelect: { command in
                            // First dismiss overlays and refocus
                            dismissAllOverlays()

                            // Then after a short delay, insert the command
                            // This ensures the editor has focus when the notification is posted
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                shouldRefocusEditor = true

                                // Wait for refocus to complete, then insert
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    insertSlashCommand(command)
                                }
                            }
                        },
                        onDismiss: {
                            dismissAllOverlays()
                            refocusAfterDismiss()
                        },
                        darkMode: darkMode
                    )
                    .zIndex(1000)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                }

                // Mention menu
                if showMentionMenu {
                    MentionMenu(
                        position: mentionMenuPosition,
                        searchQuery: mentionSearchQuery,
                        onSelect: { entity in
                            insertMention(entity)
                            dismissAllOverlays()
                            refocusAfterDismiss()
                        },
                        onDismiss: {
                            dismissAllOverlays()
                            refocusAfterDismiss()
                        },
                        darkMode: darkMode
                    )
                    .zIndex(1000)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                }

                // Selection formatting menu
                if showSelectionMenu && !showSlashMenu && !showMentionMenu {
                     SelectionFormattingMenu(
                        position: selectionMenuPosition,
                        compact: compact,
                        onDismiss: { showSelectionMenu = false }
                     )
                     .zIndex(900)
                     .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .onAppear { containerSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in containerSize = newSize }
            .onChange(of: isOverlayVisible) { _, visible in
                if visible {
                    installOutsideClickDismissMonitor()
                } else {
                    removeOutsideClickDismissMonitor()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cosmoDismissEditorOverlays)) { _ in
                dismissAllOverlays()
            }
            .onDisappear {
                removeOutsideClickDismissMonitor()
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showSlashMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showMentionMenu)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showSelectionMenu)
    }

    // MARK: - Overlay Helpers

    private func dismissAllOverlays() {
        showSlashMenu = false
        showMentionMenu = false
        // showSelectionMenu = false // Don't aggressively dismiss selection menu on outside clicks within editor?
        // Actually, outside click should dismiss it.
        showSelectionMenu = false
    }

    private func refocusAfterDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldRefocusEditor = true
        }
    }

    private func installOutsideClickDismissMonitor() {
        guard outsideClickDismissMonitor == nil else { return }

        // Dismiss if the user clicks anywhere else in the app.
        // We trigger on mouse *up* and with a tiny delay so menu taps still register first.
        outsideClickDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        ) { event in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                NotificationCenter.default.post(name: .cosmoDismissEditorOverlays, object: nil)
            }
            return event
        }
    }

    private func removeOutsideClickDismissMonitor() {
        if let monitor = outsideClickDismissMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickDismissMonitor = nil
        }
    }

    /// Clamp menu position so it stays within visible bounds
    private func clampMenuPosition(_ raw: CGPoint, menuSize: CGSize, in containerSize: CGSize) -> CGPoint {
        let padding: CGFloat = 8
        var x = raw.x
        var y = raw.y

        // Clamp horizontally
        if x + menuSize.width > containerSize.width - padding {
            x = containerSize.width - menuSize.width - padding
        }
        if x < padding { x = padding }

        // Clamp vertically (prefer showing below cursor; flip above if needed)
        if y + menuSize.height > containerSize.height - padding {
            y = max(padding, raw.y - menuSize.height - 24)
        }
        if y < padding { y = padding }

        return CGPoint(x: x, y: y)
    }

    // MARK: - Slash Command Insertion
    private func insertSlashCommand(_ command: SlashCommand) {
        // Delegate all text manipulation to TextKitCoordinator to ensure
        // atomic operations on the text storage and avoid binding desync.
        NotificationCenter.default.post(
            name: .performSlashCommand,
            object: nil,
            userInfo: ["command": command]
        )
    }

    // MARK: - Mention Insertion
    private func insertMention(_ entity: MentionEntity) {
        let mutableText = NSMutableAttributedString(attributedString: text)

        // Find and remove the "@query" text
        let searchText = "@\(mentionSearchQuery)"
        if let range = mutableText.string.range(of: searchText, options: .backwards) {
            let nsRange = NSRange(range, in: mutableText.string)
            mutableText.deleteCharacters(in: nsRange)

            // Insert styled mention
            let mention = createMentionAttributedString(entity)
            mutableText.insert(mention, at: nsRange.location)
        }

        text = mutableText
        plainText = mutableText.string
    }

    private func createMentionAttributedString(_ entity: MentionEntity) -> NSAttributedString {
        // Use CosmoMentionColors for entity-specific, high-contrast colors
        let color = CosmoMentionColors.nsColor(for: entity.type)

        return NSAttributedString(
            string: "@\(entity.title)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: color,
                .link: "cosmo://\(entity.type.rawValue)/\(entity.id)",
                .backgroundColor: color.withAlphaComponent(0.1),  // Subtle pill background
                .underlineStyle: 0,  // No underline - cleaner look
                // Custom attributes for entity tracking (hover preview, navigation)
                NSAttributedString.Key("CosmoEntityType"): entity.type.rawValue,
                NSAttributedString.Key("CosmoEntityId"): entity.id
            ]
        )
    }
}

extension Notification.Name {
    static let cosmoDismissEditorOverlays = Notification.Name("CosmoDismissEditorOverlays")
    static let setEditorTypingAttributes = Notification.Name("SetEditorTypingAttributes")
    static let performSlashCommand = Notification.Name("PerformSlashCommand")
    static let openMentionAsFloatingBlock = Notification.Name("OpenMentionAsFloatingBlock")
}

// MARK: - Slash Commands
struct SlashCommand: Identifiable {
    let id = UUID()
    let type: SlashCommandType
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String?

    static let all: [SlashCommand] = [
        SlashCommand(type: .heading1, title: "Heading 1", subtitle: "Large section heading", icon: "textformat.size.larger", shortcut: "⌘1"),
        SlashCommand(type: .heading2, title: "Heading 2", subtitle: "Medium section heading", icon: "textformat.size", shortcut: "⌘2"),
        SlashCommand(type: .bulletList, title: "Bullet List", subtitle: "Create a bullet list", icon: "list.bullet", shortcut: "⌘L"),
        SlashCommand(type: .numberedList, title: "Numbered List", subtitle: "Create a numbered list", icon: "list.number", shortcut: nil),
        SlashCommand(type: .checkbox, title: "Checkbox", subtitle: "Track tasks with checkboxes", icon: "checkmark.square", shortcut: nil),
        SlashCommand(type: .quote, title: "Quote", subtitle: "Add a block quote", icon: "text.quote", shortcut: nil),
        SlashCommand(type: .code, title: "Code Block", subtitle: "Add code with syntax highlighting", icon: "chevron.left.forwardslash.chevron.right", shortcut: nil),
        SlashCommand(type: .divider, title: "Divider", subtitle: "Visual separation between sections", icon: "minus", shortcut: nil),
        SlashCommand(type: .callout, title: "Callout", subtitle: "Highlight important information", icon: "lightbulb", shortcut: nil),
        SlashCommand(type: .linkIdea, title: "Link Idea", subtitle: "Reference an existing idea", icon: "lightbulb.fill", shortcut: nil),
        SlashCommand(type: .linkTask, title: "Link Task", subtitle: "Reference an existing task", icon: "checkmark.circle.fill", shortcut: nil),
        SlashCommand(type: .linkContent, title: "Link Content", subtitle: "Reference existing content", icon: "doc.fill", shortcut: nil),
    ]
}

enum SlashCommandType {
    case heading1, heading2
    case bulletList, numberedList, checkbox
    case quote, code, divider, callout
    case linkIdea, linkTask, linkContent
}

// MARK: - Mention Entity
struct MentionEntity: Identifiable {
    let id: Int64
    let uuid: String
    let type: EntityType
    let title: String
    let subtitle: String?
}
