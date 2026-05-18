// CosmoOS/UI/FocusMode/Connection/ConnectionMastheadView.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// The Masthead is the concept as a ritual object. Display-serif title,
// gilt filigree above and below, concept-type picker, inline maturity crystal,
// and a single small-caps stats line. Everything else in the Forge orbits this.

import SwiftUI

struct ConnectionMastheadView: View {

    // MARK: - Inputs

    @Binding var title: String
    @Binding var conceptType: ConceptFrameworkType

    /// Number of sections with at least one item. Drives crystal.
    let filledCount: Int

    /// Stats line inputs.
    let sourceCount: Int
    let insightCount: Int

    /// Commit callbacks — fired on title commit.
    var onTitleCommit: (String) -> Void = { _ in }

    // MARK: - Local state

    @FocusState private var titleFocused: Bool
    @State private var draftTitle: String = ""
    @State private var didInit: Bool = false

    private var isTitlePlaceholder: Bool { title.trimmingCharacters(in: .whitespaces).isEmpty }

    private var titleDisplay: String {
        isTitlePlaceholder ? placeholderTitle : title
    }

    private var placeholderTitle: String {
        "Unnamed \(conceptType.displayName)"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: DS.space16) {
            topFiligree
            titleBlock
            typeRow
            statsLine
            bottomFiligree
        }
        .padding(.horizontal, DS.space24)
        .padding(.vertical, DS.space20)
        .frame(maxWidth: 720)
        .onAppear {
            if !didInit {
                draftTitle = title
                didInit = true
            }
        }
        .onChange(of: title) { _, new in
            if !titleFocused { draftTitle = new }
        }
    }

    // MARK: - Title

    @ViewBuilder
    private var titleBlock: some View {
        ZStack {
            if titleFocused {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(DS.displaySerif)
                    .tracking(0.4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.inkWash)
                    .focused($titleFocused)
                    .onSubmit {
                        commitTitle()
                        titleFocused = false
                    }
            } else {
                Text(titleDisplay)
                    .font(DS.displaySerif)
                    .tracking(0.4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isTitlePlaceholder ? DS.inkFaded : DS.inkWash)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draftTitle = title
                        titleFocused = true
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Concept title: \(titleDisplay)")
        .accessibilityHint("Tap to rename")
        .onChange(of: titleFocused) { _, focused in
            if !focused { commitTitle() }
        }
    }

    private func commitTitle() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != title else { return }
        title = trimmed
        onTitleCommit(trimmed)
    }

    // MARK: - Type + Crystal row

    private var typeRow: some View {
        HStack(spacing: DS.space16) {
            hairRule
            conceptTypeMenu
            Text("·")
                .font(DS.smallCaps)
                .foregroundStyle(DS.giltMuted)
            MaturityCrystalInline(filledCount: filledCount, glyphSize: 9)
            hairRule
        }
        .frame(maxWidth: .infinity)
    }

    private var hairRule: some View {
        Rectangle()
            .fill(DS.sepiaSubtle)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    private var conceptTypeMenu: some View {
        Menu {
            ForEach(ConceptFrameworkType.allCases, id: \.self) { type in
                Button {
                    conceptType = type
                } label: {
                    Label(type.displayName, systemImage: conceptType == type ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(conceptType.displayName.uppercased())
                    .font(DS.smallCaps)
                    .tracking(1.6)
                    .foregroundStyle(DS.giltMuted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.giltMuted)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, 5)
            .background(
                Capsule().stroke(DS.gilt.opacity(0.35), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Concept type: \(conceptType.displayName)")
    }

    // MARK: - Stats line

    private var statsLine: some View {
        Text(statsText)
            .font(DS.smallCaps)
            .tracking(1.4)
            .foregroundStyle(DS.inkFaded)
            .accessibilityLabel("\(sourceCount) sources, \(filledCount) of \(ConnectionSectionType.allCases.count) stations, \(insightCount) insights")
    }

    private var statsText: String {
        let sources = "\(sourceCount) SOURCE\(sourceCount == 1 ? "" : "S")"
        let stations = "\(filledCount)/\(ConnectionSectionType.allCases.count) STATIONS"
        let insights = "\(insightCount) INSIGHT\(insightCount == 1 ? "" : "S")"
        return "\(sources)  ·  \(stations)  ·  \(insights)"
    }

    // MARK: - Filigree

    private var topFiligree: some View {
        filigreeRow(flip: false)
    }

    private var bottomFiligree: some View {
        filigreeRow(flip: true)
    }

    private func filigreeRow(flip: Bool) -> some View {
        HStack(spacing: DS.space12) {
            filigreeDot
            Rectangle()
                .fill(DS.gilt.opacity(0.4))
                .frame(height: 0.75)
                .frame(maxWidth: .infinity)
            Image(systemName: flip ? "diamond" : "diamond.fill")
                .font(.system(size: 10))
                .foregroundStyle(DS.gilt.opacity(0.7))
            Rectangle()
                .fill(DS.gilt.opacity(0.4))
                .frame(height: 0.75)
                .frame(maxWidth: .infinity)
            filigreeDot
        }
        .frame(maxWidth: .infinity)
    }

    private var filigreeDot: some View {
        Circle()
            .fill(DS.gilt.opacity(0.55))
            .frame(width: 3, height: 3)
    }
}

#if DEBUG
private struct _MastheadPreviewHarness: View {
    @State var title: String
    @State var conceptType: ConceptFrameworkType
    var filled: Int
    var sources: Int
    var insights: Int

    var body: some View {
        ConnectionMastheadView(
            title: $title,
            conceptType: $conceptType,
            filledCount: filled,
            sourceCount: sources,
            insightCount: insights
        )
        .padding(40)
        .background(DS.vellum)
    }
}

#Preview("Masthead — Filled") {
    _MastheadPreviewHarness(
        title: "Tony Robbins & Alex Hormozi",
        conceptType: .mentalModel,
        filled: 5,
        sources: 3,
        insights: 12
    )
}

#Preview("Masthead — Empty") {
    _MastheadPreviewHarness(
        title: "",
        conceptType: .framework,
        filled: 0,
        sources: 0,
        insights: 0
    )
}
#endif
