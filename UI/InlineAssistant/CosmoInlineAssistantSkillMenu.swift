// CosmoOS/UI/InlineAssistant/CosmoInlineAssistantSkillMenu.swift
// The / skills picker in the assistant menu grammar: RECENT / EDITS / ANSWERS /
// UTILITIES sections while browsing, flat ranked results while searching, a
// detail strip carrying the highlighted skill's summary, full keyboard control.
// July 2026 rebuild (was a private card-chassis struct in the bar)

import Foundation
import SwiftUI

// MARK: - Recency store

/// Persisted per-skill last-used timestamps so the / menu can surface the
/// user's go-to skills first. UserDefaults-backed; injectable for tests.
struct CosmoInlineSkillRecencyStore {
    private let defaults: UserDefaults
    private let key = "cosmo.inline.skill.recency"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordUse(_ skillID: String, at date: Date = Date()) {
        var stamps = (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        stamps[skillID] = date.timeIntervalSince1970
        defaults.set(stamps, forKey: key)
    }

    func recentIDs(limit: Int) -> [String] {
        let stamps = (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        return stamps
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}

// MARK: - Model

@MainActor
@Observable
final class CosmoInlineSkillMenuModel {
    enum Utility: String, CaseIterable, Identifiable {
        case clearSession
        case createSkill
        case openStudio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clearSession: return "Clear Conversation"
            case .createSkill: return "New Skill…"
            case .openStudio: return "Assistant Studio…"
            }
        }

        var icon: String {
            switch self {
            case .clearSession: return "trash"
            case .createSkill: return "plus.square.dashed"
            case .openStudio: return "slider.horizontal.3"
            }
        }
    }

    enum Entry: Identifiable {
        case skill(CosmoInlineSkillDefinition)
        case utility(Utility)

        var id: String {
            switch self {
            case .skill(let skill): return skill.id
            case .utility(let utility): return "utility:\(utility.rawValue)"
            }
        }
    }

    struct Section: Identifiable {
        let title: String?
        let startIndex: Int
        let entries: [Entry]
        var id: String { title ?? "results" }
    }

    private(set) var sections: [Section] = []
    private(set) var flattened: [Entry] = []
    private(set) var highlightedIndex = 0
    private(set) var isBrowsing = true

    private let registry: CosmoInlineSkillRegistry
    private let recency: CosmoInlineSkillRecencyStore

    init(
        registry: CosmoInlineSkillRegistry = CosmoInlineSkillRegistry(),
        recency: CosmoInlineSkillRecencyStore = CosmoInlineSkillRecencyStore()
    ) {
        self.registry = registry
        self.recency = recency
    }

    var highlightedEntry: Entry? {
        flattened.indices.contains(highlightedIndex) ? flattened[highlightedIndex] : nil
    }

    var highlightedSkill: CosmoInlineSkillDefinition? {
        if case .skill(let skill) = highlightedEntry { return skill }
        return nil
    }

    func moveHighlight(_ delta: Int) {
        highlightedIndex = CosmoAssistantMenuHighlightPolicy.moved(
            highlightedIndex, by: delta, count: flattened.count
        )
    }

    func setHighlight(_ index: Int) {
        highlightedIndex = CosmoAssistantMenuHighlightPolicy.clamped(index, count: flattened.count)
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isBrowsing = true
            rebuildBrowsing()
        } else {
            isBrowsing = false
            rebuildSearch(query: trimmed)
        }
    }

    private func rebuildBrowsing() {
        let skills = registry.enabledSkills
        let recentIDs = recency.recentIDs(limit: 3)
        let recents = recentIDs.compactMap { id in skills.first { $0.id == id } }
        let recentSet = Set(recents.map(\.id))

        var built: [Section] = []
        var flat: [Entry] = []

        func appendSection(_ title: String, _ entries: [Entry]) {
            guard !entries.isEmpty else { return }
            built.append(Section(title: title, startIndex: flat.count, entries: entries))
            flat.append(contentsOf: entries)
        }

        appendSection("RECENT", recents.map(Entry.skill))
        appendSection(
            "EDITS",
            skills.filter { $0.route == .action && !recentSet.contains($0.id) }.map(Entry.skill)
        )
        appendSection(
            "ANSWERS",
            skills.filter { $0.route == .answer && !recentSet.contains($0.id) }.map(Entry.skill)
        )
        appendSection("UTILITIES", Utility.allCases.map(Entry.utility))

        apply(sections: built, flattened: flat)
    }

    private func rebuildSearch(query: String) {
        let matches = registry.matchingSlashCommands(query: query, limit: 10).map(Entry.skill)
        apply(
            sections: [Section(title: nil, startIndex: 0, entries: matches)],
            flattened: matches
        )
    }

    private func apply(sections: [Section], flattened flat: [Entry]) {
        self.sections = sections
        flattened = flat
        highlightedIndex = CosmoAssistantMenuHighlightPolicy.clamped(highlightedIndex, count: flat.count)
    }
}

// MARK: - View

struct CosmoInlineAssistantSkillMenu: View {
    let model: CosmoInlineSkillMenuModel
    let searchText: String
    let selectedSkillID: String?
    let onCommit: (CosmoInlineSkillMenuModel.Entry) -> Void

    private let menuWidth: CGFloat = 320
    private let listMaxHeight: CGFloat = 296

    var body: some View {
        VStack(spacing: 0) {
            header
            CosmoGradientDivider()
            content
            detailStrip
            CosmoKeyboardFooter(selectLabel: "Use Skill")
        }
        .frame(width: menuWidth)
        .cosmoMenuChrome(cornerRadius: 14)
        .onAppear {
            model.setHighlight(0)
            model.update(query: searchText)
        }
        .onChange(of: searchText) { _, value in
            model.update(query: value)
        }
    }

    private var header: some View {
        HStack(spacing: DS.space10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.accentSoft)
                    .frame(width: 26, height: 26)
                Image(systemName: "slash.circle")
                    .font(DS.caption.weight(.semibold))
                    .foregroundStyle(DS.accent)
            }
            .accessibilityHidden(true)

            Text("Skills")
                .font(DS.callout.weight(.semibold))
                .foregroundStyle(DS.text)

            Spacer(minLength: 0)

            Text("\(skillCount)")
                .font(DS.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .contentTransition(.numericText())
                .accessibilityLabel("\(skillCount) skills")
        }
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space10)
    }

    private var skillCount: Int {
        model.flattened.reduce(into: 0) { count, entry in
            if case .skill = entry { count += 1 }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.flattened.isEmpty {
            emptyState
        } else {
            listView
        }
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.sections) { section in
                        if let title = section.title {
                            CosmoAssistantMenuSectionHeader(title: title)
                        }
                        ForEach(Array(section.entries.enumerated()), id: \.element.id) { offset, entry in
                            entryRow(entry, index: section.startIndex + offset)
                        }
                    }
                }
                .padding(.vertical, DS.space6)
            }
            .frame(maxHeight: listMaxHeight)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: model.highlightedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newIndex)
                }
            }
        }
    }

    private func entryRow(_ entry: CosmoInlineSkillMenuModel.Entry, index: Int) -> some View {
        CosmoAssistantMenuRow(
            icon: icon(for: entry),
            iconTint: tint(for: entry),
            title: title(for: entry),
            trailingHint: hint(for: entry),
            showsCheckmark: isArmed(entry),
            isHighlighted: index == model.highlightedIndex
        )
        .id(index)
        .onTapGesture {
            CosmicHaptics.shared.play(.selection)
            onCommit(entry)
        }
        .onHover { hovering in
            if hovering, model.highlightedIndex != index {
                model.setHighlight(index)
            }
        }
    }

    @ViewBuilder
    private var detailStrip: some View {
        if let skill = model.highlightedSkill {
            CosmoAssistantMenuDetailStrip(
                icon: skill.route == .action ? "pencil.and.scribble" : "text.bubble",
                text: skill.summary,
                trailing: skill.displayedModelLabel
            )
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.space4) {
            Text("No matching skills")
                .font(DS.callout.weight(.medium))
                .foregroundStyle(DS.text)
            Text("Try a shorter command, or create one in the Assistant Studio.")
                .font(DS.caption)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.space12)
        .padding(.vertical, DS.space12)
    }

    // MARK: Row presentation

    private func icon(for entry: CosmoInlineSkillMenuModel.Entry) -> String {
        switch entry {
        case .skill(let skill): return skill.icon
        case .utility(let utility): return utility.icon
        }
    }

    private func tint(for entry: CosmoInlineSkillMenuModel.Entry) -> Color? {
        if case .utility(.clearSession) = entry { return DS.red }
        return nil
    }

    private func title(for entry: CosmoInlineSkillMenuModel.Entry) -> String {
        switch entry {
        case .skill(let skill): return skill.name
        case .utility(let utility): return utility.title
        }
    }

    private func hint(for entry: CosmoInlineSkillMenuModel.Entry) -> String? {
        if case .skill(let skill) = entry { return skill.displayedModelLabel }
        return nil
    }

    private func isArmed(_ entry: CosmoInlineSkillMenuModel.Entry) -> Bool {
        if case .skill(let skill) = entry { return skill.id == selectedSkillID }
        return false
    }
}
