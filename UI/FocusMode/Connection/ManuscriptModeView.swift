// CosmoOS/UI/FocusMode/Connection/ManuscriptModeView.swift
// April 2026 — Connection Focus Mode V2 "The Crucible"
//
// Manuscript mode flattens the spatial workshop into a single serif-typeset
// reading flow — the framework as a printed document. Each populated station
// becomes a chapter: gilt dropcap-like header, body lines as serif bullets, no
// chrome. This is the "read it as if it were a book" moment — a final
// check before the framework leaves the crucible.

import SwiftUI

struct ManuscriptModeView: View {

    let title: String
    let conceptType: ConceptFrameworkType
    let sections: [ConnectionSection]
    let onDismiss: () -> Void

    private var populatedSections: [ConnectionSection] {
        sections
            .filter { !$0.items.isEmpty }
            .sorted { $0.type.sortOrder < $1.type.sortOrder }
    }

    // Dark themes read the manuscript in a dark room; light themes keep vellum.
    private var paper: Color {
        DS.usesImmersiveFocusAppearance ? DS.bg : DS.vellum
    }

    private var ink: Color {
        DS.usesImmersiveFocusAppearance ? DS.text : DS.inkWash
    }

    private var inkSecondary: Color {
        DS.usesImmersiveFocusAppearance ? DS.textMuted : DS.inkFaded
    }

    private var hairline: Color {
        DS.usesImmersiveFocusAppearance ? DS.border : DS.sepiaBorder
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            paper.ignoresSafeArea()
            scrollBody
            dismissButton
        }
    }

    // MARK: - Scroll body

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                masthead
                ForEach(populatedSections) { section in
                    chapter(for: section)
                }
                colophon
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 48)
            .padding(.top, 80)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .center, spacing: 14) {
            filigree
            Text(title.isEmpty ? "Untitled Framework" : title)
                .font(DS.displaySerif)
                .tracking(0.4)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(conceptType.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(2.4)
                .foregroundStyle(DS.giltMuted)
            filigree
        }
        .frame(maxWidth: .infinity)
    }

    private var filigree: some View {
        HStack(spacing: 10) {
            Rectangle().fill(DS.gilt.opacity(0.6)).frame(height: 0.5)
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(DS.gilt.opacity(0.75))
            Rectangle().fill(DS.gilt.opacity(0.6)).frame(height: 0.5)
        }
        .frame(maxWidth: 280)
    }

    // MARK: - Chapter

    private func chapter(for section: ConnectionSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            chapterHeader(section)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(section.type.accentColor.opacity(0.7))
                            .frame(width: 5, height: 5)
                            .padding(.top, 9)
                        if let linkedUUID = item.linkedConnectionUUID {
                            ConnectionLinkPill(title: item.resolvedPlainText) {
                                ConnectionLinkOpener.open(uuid: linkedUUID)
                            }
                        } else {
                            ConnectionLinkedText(
                                text: item.resolvedPlainText,
                                font: .system(size: 16, weight: .regular, design: .serif),
                                color: ink
                            )
                            .lineSpacing(4)
                        }
                    }
                }
            }
        }
    }

    private func chapterHeader(_ section: ConnectionSection) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(section.type.accentColor)
                .frame(width: 6, height: 6)
            Text(section.type.displayName.uppercased())
                .font(DS.smallCaps)
                .tracking(2.0)
                .foregroundStyle(section.type.accentColor)
            Rectangle().fill(section.type.accentColor.opacity(0.3)).frame(height: 0.5)
        }
    }

    private var colophon: some View {
        VStack(spacing: 10) {
            filigree
            Text("— FIN —")
                .font(DS.smallCaps)
                .tracking(3.0)
                .foregroundStyle(DS.giltMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(inkSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().stroke(hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(24)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Dismiss manuscript mode")
    }
}
