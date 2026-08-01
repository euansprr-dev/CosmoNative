// CosmoOS/Editor/SlashCommandMenu.swift
// The block insert menu: one dense, sectioned list — Apple-menu density,
// monochrome ink icons, trailing markdown-alias hints, elements inline.
// July 2026 redesign (Notes overhaul Phase 2).

import SwiftUI

/// Type-through slash menu: the query lives in the document text after the
/// "/" — this view never takes focus. Filtering, the highlighted index, and
/// keyboard events (routed from the text view's coordinator) all arrive from
/// the host; the menu is purely presentational plus hover/click.
struct SlashCommandMenu: View {
    let position: CGPoint
    /// Live query typed after the "/" (display only — filtering is upstream).
    let query: String
    /// Already filtered against the query, in display order.
    let commands: [SlashCommand]
    let selectedIndex: Int
    let onHighlight: (Int) -> Void
    let onSelect: (SlashCommand) -> Void
    let onDismiss: () -> Void
    var darkMode: Bool = false  // Dark glass mode for Thinkspace blocks

    @State private var appeared = false
    @State private var scrollMetrics = CortexScrollMetricsStore()

    private let menuWidth: CGFloat = 300
    private let menuHeight: CGFloat = 380
    private let footerHeight: CGFloat = 34

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Browsing keeps the full catalog box; a narrowed search hugs its
    /// results instead of towing 300pt of empty glass under two rows.
    /// Quantized to 4-row steps: resizing the frame per keystroke made the
    /// glass backdrop + shadow compositor re-layout on every character (see
    /// glass_layer_animated_frame_latch for why glass resizes are hostile).
    private var resolvedHeight: CGFloat {
        guard isSearching else { return menuHeight }
        let rows = ceil(CGFloat(max(1, commands.count)) / 4) * 4 * 32
        return min(menuHeight, rows + footerHeight + DS.space6 * 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            commandListView
            CosmoKeyboardFooter(darkMode: darkMode)
        }
        .frame(width: menuWidth, height: resolvedHeight, alignment: .top)
        .cosmoMenuChrome(cornerRadius: 14, darkMode: darkMode)
        .position(x: position.x + (menuWidth / 2), y: position.y + (resolvedHeight / 2))
        .onAppear {
            // No haptic here — cosmoMenuChrome already plays .menuAppear;
            // this fired the entrance buzz twice on the same frame.
            withAnimation(ProMotionSprings.menuAppear) { appeared = true }
        }
    }

    // MARK: - List

    private var commandListView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        // While browsing, a section header introduces each
                        // group; while searching, results are a flat ranked
                        // list — headers would fight the ranking.
                        if !isSearching, showsSectionHeader(at: index) {
                            sectionHeader(command.section)
                        }
                        commandRow(command: command, index: index)
                    }
                }
                .padding(.vertical, DS.space6)
                // Kill the legacy fat scroller ("always show scroll bars")
                // and draw the app's thin capsule chrome instead.
                .background(CortexScrollViewIntrospector { scrollMetrics.publish($0) })
            }
            .frame(maxHeight: resolvedHeight - footerHeight)
            .scrollBounceBehavior(.basedOnSize)
            .cortexThinScrollbar(store: scrollMetrics)
            .onChange(of: selectedIndex) { _, newIndex in
                CosmicHaptics.shared.play(.threshold)
                // Unanimated: an animated scroll inside a ScrollView whose
                // content just changed (filter keystroke resets the index)
                // fought the fresh layout every character.
                proxy.scrollTo(commands[safe: newIndex]?.id)
            }
        }
    }

    private func showsSectionHeader(at index: Int) -> Bool {
        guard let command = commands[safe: index] else { return false }
        guard index > 0 else { return true }
        return commands[index - 1].section != command.section
    }

    private func sectionHeader(_ section: SlashCommandSection) -> some View {
        // Capitalized source + smallCaps() — .smallCaps() on an UPPERCASE raw
        // value is a no-op; ONE small-caps dialect app-wide.
        Text(section.rawValue.capitalized)
            .font(DS.smallCaps)
            .tracking(DS.smallCapsTracking)
            // 0.62 clears AA on the dark chrome (0.42 sat at ~3.3:1 on a
            // 10pt tracked label).
            .foregroundStyle(darkMode ? Color.white.opacity(0.62) : DS.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.space12)
            .padding(.top, DS.space8)
            .padding(.bottom, DS.space2)
            .accessibilityAddTraits(.isHeader)
    }

    private func commandRow(command: SlashCommand, index: Int) -> some View {
        SlashCommandRow(
            command: command,
            isSelected: index == selectedIndex,
            darkMode: darkMode
        )
        // Identity = the command, not its position: with `.id(index)`,
        // filtering shifted commands between indices and SwiftUI destroyed/
        // recreated every row (and its gesture recognizers) per keystroke.
        .id(command.id)
        .onTapGesture {
            CosmicHaptics.shared.play(.selection)
            onSelect(command)
        }
        .onHover { isHovered in
            if isHovered, selectedIndex != index {
                onHighlight(index)
            }
        }
    }
}

// MARK: - Slash Command Row

/// One 32pt row: monochrome ink icon, medium title, trailing mono alias hint.
/// Selection is a soft accent wash + hairline — never a solid fill.
struct SlashCommandRow: View {
    let command: SlashCommand
    let isSelected: Bool
    var darkMode: Bool = false

    private var textPrimary: Color { darkMode ? .white : DS.documentText }
    private var inkColor: Color { darkMode ? Color.white.opacity(0.62) : DS.documentTextSecondary }
    private var hintColor: Color { darkMode ? Color.white.opacity(0.34) : DS.documentTextMuted.opacity(0.8) }
    private var accentColor: Color { darkMode ? Color.white.opacity(0.85) : DS.accent }

    var body: some View {
        HStack(spacing: DS.space10) {
            Image(systemName: DocumentElementSymbol.validName(command.icon))
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? accentColor : inkColor)
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)

            Text(command.title)
                .font(DS.callout.weight(.medium))
                .foregroundStyle(textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(DS.keycap)
                    .foregroundStyle(hintColor)
            }
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? selectionFill : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? selectionHairline : Color.clear, lineWidth: 1)
                )
                .padding(.horizontal, DS.space6)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectionFill: Color {
        darkMode ? Color.white.opacity(0.10) : DS.accentSoft
    }

    private var selectionHairline: Color {
        darkMode ? Color.white.opacity(0.16) : DS.accent.opacity(0.22)
    }
}

// MARK: - Element Creation Menu

/// The "New Element" form: name, tone, icon — with a live preview of the
/// element header rendering exactly as it will appear in the document.
struct ElementCreationMenu: View {
    let position: CGPoint
    let onCreate: (String, String, String) -> Void
    let onDismiss: () -> Void
    var darkMode: Bool = false

    @State private var title = ""
    @State private var icon = NoteElementIconCatalog.curated.first?.symbol ?? "square.dashed"
    @State private var toneID = NoteInkPalette.defaultToneID
    @State private var iconQuery = ""
    @State private var iconScrollMetrics = CortexScrollMetricsStore()
    @FocusState private var titleFocused: Bool

    private let menuWidth: CGFloat = 320
    private let menuHeight: CGFloat = 352

    private var textPrimary: Color { darkMode ? .white : DS.documentText }
    private var textSecondary: Color { darkMode ? Color.white.opacity(0.62) : DS.documentTextSecondary }
    private var fieldFill: Color { darkMode ? Color.white.opacity(0.08) : DS.glassInputFill.opacity(0.46) }
    private var canCreate: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var tone: NoteInkTone { NoteInkPalette.tone(toneID) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            livePreview
            nameField
            toneRow
            iconPicker
            footerRow
        }
        .padding(DS.space12)
        .frame(width: menuWidth, height: menuHeight, alignment: .top)
        .cosmoMenuChrome(cornerRadius: 14, darkMode: darkMode)
        .position(x: position.x + (menuWidth / 2), y: position.y + (menuHeight / 2))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                titleFocused = true
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    /// The element header, rendered with the exact chrome it will have in the
    /// document — what you see is what you insert.
    private var livePreview: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "chevron.right")
                .font(DS.caption2.weight(.semibold))
                .foregroundStyle(textSecondary.opacity(0.7))
                .rotationEffect(.degrees(90))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tone.wash(darkMode: darkMode))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: DocumentElementSymbol.validName(icon))
                        .font(DS.caption.weight(.medium))
                        .foregroundStyle(tone.ink(darkMode: darkMode))
                )
            // DS.headline — the card this preview promises now renders its
            // title at 15 semibold ("what you see is what you insert").
            Text(title.isEmpty ? "New Element" : title)
                .font(DS.headline)
                .foregroundStyle(title.isEmpty ? textSecondary : textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.space10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tone.wash(darkMode: darkMode).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tone.hairline(darkMode: darkMode), lineWidth: 1)
        )
        .animation(ProMotionSprings.snappy, value: toneID)
        .accessibilityHidden(true)
    }

    private var nameField: some View {
        TextField("Element name", text: $title)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(textPrimary)
            .focused($titleFocused)
            .onSubmit { createIfPossible() }
            .padding(.horizontal, DS.space10)
            .padding(.vertical, DS.space8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fieldFill))
            .accessibilityLabel("Element name")
    }

    private var toneRow: some View {
        HStack(spacing: DS.space8) {
            ForEach(NoteInkPalette.tones) { option in
                toneSwatch(option)
            }
            Spacer(minLength: 0)
        }
    }

    private func toneSwatch(_ option: NoteInkTone) -> some View {
        let isSelected = option.id == toneID
        return Button {
            withAnimation(ProMotionSprings.snappy) { toneID = option.id }
        } label: {
            Circle()
                .fill(option.ink(darkMode: darkMode).opacity(isSelected ? 1 : 0.75))
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? option.ink(darkMode: darkMode).opacity(0.5) : Color.clear,
                            lineWidth: 2
                        )
                        .padding(-3)
                )
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(option.label)
        .accessibilityLabel("\(option.label) color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: DS.space6) {
            TextField("Search icons", text: $iconQuery)
                .textFieldStyle(.plain)
                .font(DS.caption)
                .foregroundStyle(textPrimary)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fieldFill))
                .accessibilityLabel("Search icons")

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: DS.space6), count: 8), spacing: DS.space6) {
                    ForEach(NoteElementIconCatalog.matching(iconQuery), id: \.symbol) { option in
                        iconCell(option)
                    }
                }
                .background(CortexScrollViewIntrospector { iconScrollMetrics.publish($0) })
            }
            .frame(height: 108)
            .scrollBounceBehavior(.basedOnSize)
            .cortexThinScrollbar(store: iconScrollMetrics)
        }
    }

    private func iconCell(_ option: NoteElementIconCatalog.Option) -> some View {
        let isSelected = option.symbol == icon
        return Button {
            icon = option.symbol
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = option.suggestedName
            }
        } label: {
            Image(systemName: DocumentElementSymbol.validName(option.symbol))
                .font(DS.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? tone.ink(darkMode: darkMode) : textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? tone.wash(darkMode: darkMode) : fieldFill.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isSelected ? tone.hairline(darkMode: darkMode) : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.suggestedName)
        .accessibilityLabel(option.suggestedName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footerRow: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .buttonStyle(.plain)
                .font(DS.caption)
                .foregroundStyle(textSecondary)
            Spacer(minLength: 0)
            Button("Create") { createIfPossible() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canCreate)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func createIfPossible() {
        guard canCreate else { return }
        onCreate(title, DocumentElementSymbol.validName(icon), toneID)
    }
}

// MARK: - Icon Catalog

/// The element icon vocabulary: a curated first screen plus a keyword-searchable
/// catalog. Modern, filled-free SF Symbols that read at 13pt.
enum NoteElementIconCatalog {
    struct Option {
        let symbol: String
        let suggestedName: String
        let keywords: [String]

        init(_ symbol: String, _ suggestedName: String, _ keywords: [String] = []) {
            self.symbol = symbol
            self.suggestedName = suggestedName
            self.keywords = keywords
        }
    }

    /// First screen — no query. Two rows above the fold, ~3 screens total.
    static let curated: [Option] = [
        Option("square.dashed", "Section", ["structure", "box"]),
        Option("lightbulb", "Idea", ["spark", "inspiration"]),
        Option("person.2", "Meeting", ["people", "audience"]),
        Option("book", "Reading", ["book", "study"]),
        Option("scale.3d", "Decision", ["weigh", "choice"]),
        Option("sun.max", "Journal", ["day", "morning"]),
        Option("tray.full", "Inbox", ["collect", "bank"]),
        Option("target", "Goal", ["aim", "objective"]),
        Option("calendar", "Schedule", ["date", "plan"]),
        Option("checkmark.circle", "Done", ["complete", "task"]),
        Option("flag", "Priority", ["important", "urgent"]),
        Option("pin", "Pinned", ["stick", "keep"]),
        Option("quote.opening", "Quote", ["citation", "words"]),
        Option("text.quote", "Excerpt", ["passage"]),
        Option("list.bullet.indent", "Outline", ["plan", "structure"]),
        Option("brain", "Thinking", ["mind", "brainstorm"]),
        Option("sparkles", "Insight", ["magic", "aha"]),
        Option("questionmark.circle", "Question", ["ask", "open"]),
        Option("exclamationmark.triangle", "Warning", ["caution", "risk"]),
        Option("bolt", "Action", ["energy", "fast"]),
        Option("flame", "Hot", ["fire", "trending"]),
        Option("heart", "Favorite", ["love", "like"]),
        Option("star", "Starred", ["best", "highlight"]),
        Option("map", "Map", ["territory", "plan"]),
    ]

    /// The long tail, reachable by search only.
    static let extended: [Option] = [
        Option("folder", "Folder", ["directory", "group"]),
        Option("archivebox", "Archive", ["store", "old"]),
        Option("doc.text", "Draft", ["document", "page"]),
        Option("note.text", "Note", ["memo"]),
        Option("bookmark", "Bookmark", ["save", "later"]),
        Option("tag", "Tag", ["label", "category"]),
        Option("link", "Link", ["url", "connection"]),
        Option("paperclip", "Attachment", ["clip", "file"]),
        Option("magnifyingglass", "Research", ["search", "investigate"]),
        Option("books.vertical", "Library", ["reference", "collection"]),
        Option("graduationcap", "Learning", ["course", "school"]),
        Option("pencil.line", "Writing", ["pen", "draft"]),
        Option("highlighter", "Highlight", ["marker"]),
        Option("scissors", "Clip", ["cut", "snippet"]),
        Option("photo", "Media", ["image", "picture"]),
        Option("play.rectangle", "Video", ["film", "reel"]),
        Option("waveform", "Audio", ["sound", "voice"]),
        Option("mic", "Recording", ["voice", "dictation"]),
        Option("music.note", "Music", ["song"]),
        Option("camera", "Photo", ["shot"]),
        Option("chart.line.uptrend.xyaxis", "Metrics", ["growth", "analytics", "stats"]),
        Option("chart.pie", "Breakdown", ["share", "analytics"]),
        Option("dollarsign.circle", "Money", ["finance", "budget"]),
        Option("cart", "Shopping", ["buy", "groceries"]),
        Option("gift", "Gift", ["present", "surprise"]),
        Option("airplane", "Travel", ["trip", "flight"]),
        Option("car", "Drive", ["commute"]),
        Option("house", "Home", ["house"]),
        Option("building.2", "Work", ["office", "company"]),
        Option("briefcase", "Business", ["client", "work"]),
        Option("hammer", "Build", ["make", "project"]),
        Option("wrench.adjustable", "Fix", ["repair", "tool"]),
        Option("gearshape", "Setup", ["settings", "config"]),
        Option("terminal", "Dev", ["code", "shell"]),
        Option("keyboard", "Typing", ["input"]),
        Option("cpu", "System", ["chip", "tech"]),
        Option("network", "Network", ["graph", "web"]),
        Option("globe", "World", ["global", "web"]),
        Option("safari", "Compass", ["explore", "browse"]),
        Option("location", "Place", ["map", "pin"]),
        Option("leaf", "Nature", ["plant", "green"]),
        Option("tree", "Growth", ["forest"]),
        Option("drop", "Water", ["hydrate", "liquid"]),
        Option("moon", "Night", ["sleep", "evening"]),
        Option("cloud", "Weather", ["sky"]),
        Option("snowflake", "Winter", ["cold", "frozen"]),
        Option("figure.run", "Workout", ["exercise", "fitness", "gym"]),
        Option("dumbbell", "Training", ["gym", "strength"]),
        Option("fork.knife", "Recipe", ["food", "cooking", "meal"]),
        Option("cup.and.saucer", "Coffee", ["cafe", "break"]),
        Option("pills", "Health", ["medicine", "medical"]),
        Option("cross.case", "Medical", ["doctor", "health"]),
        Option("bed.double", "Sleep", ["rest", "night"]),
        Option("face.smiling", "Mood", ["feeling", "emotion"]),
        Option("bubble.left.and.bubble.right", "Conversation", ["chat", "dialog"]),
        Option("envelope", "Email", ["mail", "message"]),
        Option("phone", "Call", ["contact"]),
        Option("person.crop.circle", "Person", ["contact", "profile"]),
        Option("person.3", "Team", ["group", "community"]),
        Option("hand.raised", "Blocked", ["stop", "wait"]),
        Option("clock", "Time", ["hour", "schedule"]),
        Option("hourglass", "Pending", ["waiting", "progress"]),
        Option("timer", "Timer", ["countdown", "pomodoro"]),
        Option("bell", "Reminder", ["notify", "alert"]),
        Option("lock", "Private", ["secret", "secure"]),
        Option("key", "Access", ["password", "unlock"]),
        Option("shield", "Security", ["protect", "guard"]),
        Option("trash", "Discard", ["delete", "remove"]),
        Option("arrow.triangle.branch", "Options", ["fork", "paths"]),
        Option("arrow.clockwise", "Routine", ["repeat", "habit"]),
        Option("infinity", "Ongoing", ["forever", "loop"]),
        Option("puzzlepiece", "Piece", ["part", "fit"]),
        Option("cube", "Object", ["3d", "thing"]),
        Option("shippingbox", "Package", ["delivery", "asset"]),
        Option("gamecontroller", "Play", ["game", "fun"]),
        Option("paintbrush", "Design", ["art", "creative"]),
        Option("paintpalette", "Palette", ["color", "art"]),
        Option("theatermasks", "Story", ["drama", "narrative"]),
        Option("film", "Scene", ["movie", "clip"]),
        Option("wand.and.stars", "Magic", ["transform", "ai"]),
        Option("atom", "Science", ["physics", "research"]),
        Option("function", "Formula", ["math", "equation"]),
        Option("number", "Reference", ["hashtag", "id"]),
        Option("curlybraces", "Snippet", ["code", "dev"]),
        Option("diamond", "Gem", ["rare", "special"]),
        Option("crown", "Best", ["top", "winner"]),
        Option("trophy", "Win", ["achievement", "award"]),
        Option("medal", "Milestone", ["achievement"]),
        Option("rocket", "Launch", ["ship", "start"]),
        Option("paperplane", "Send", ["publish", "share"]),
        Option("megaphone", "Announce", ["marketing", "promo"]),
        Option("eye", "Watch", ["observe", "review"]),
        Option("binoculars", "Scout", ["explore", "research"]),
    ]

    static func matching(_ query: String) -> [Option] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return curated }
        return (curated + extended).filter { option in
            option.symbol.contains(normalized)
                || option.suggestedName.lowercased().contains(normalized)
                || option.keywords.contains { $0.contains(normalized) }
        }
    }
}

// MARK: - Safe Array Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
