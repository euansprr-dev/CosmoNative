// CosmoOS/UI/FocusMode/Inquiry/Crystallize/ConnectionDraftCard.swift
// Editable card for one branch-to-Connection crystallization draft.

import SwiftUI

@MainActor
struct ConnectionDraftCard: View {
    @Binding var candidate: CrystallizationOutput.ConnectionCandidate
    @State private var expandedSections: Set<ConnectionSectionType> = Set(ConnectionSectionType.allCases)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            header
            if candidate.materialCount < 3 {
                lowMaterialBanner
            }
            sectionList
        }
        .padding(DS.space16)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(candidate.accepted ? DS.accent.opacity(0.42) : DS.borderSubtle, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            Image(systemName: candidate.accepted ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(candidate.accepted ? DS.accent : CosmoColors.textTertiary)
                .padding(.top, 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Connection title", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(CosmoColors.textPrimary)
                HStack(spacing: 8) {
                    chip("\(candidate.materialCount) captures")
                    chip("\(filledSections.count) sections")
                    if let concept = candidate.proposedConcept, !concept.isEmpty {
                        chip(concept)
                    }
                }
            }

            Spacer(minLength: DS.space12)

            Toggle("Skip", isOn: skippedBinding)
                .toggleStyle(.switch)
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
        }
    }

    private var lowMaterialBanner: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.orange)
                .accessibilityHidden(true)
            Text("Not enough material for an automatic Connection.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(CosmoColors.textSecondary)
            Spacer()
            Button("Include anyway") {
                candidate.accepted = true
            }
            .buttonStyle(.plain)
            .font(CosmoTypography.caption)
            .foregroundStyle(DS.accent)
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, 8)
        .background(DS.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private var sectionList: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ForEach(filledSections, id: \.self) { sectionType in
                sectionView(sectionType)
            }
            if !candidate.proposedNotes.isEmpty {
                notesView
            }
        }
    }

    private func sectionView(_ sectionType: ConnectionSectionType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(sectionType)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: sectionType.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(sectionType.accentColor)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(sectionType.displayName)
                        .font(CosmoTypography.label)
                        .foregroundStyle(CosmoColors.textPrimary)
                    Text("\(items(for: sectionType).count)")
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: expandedSections.contains(sectionType) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CosmoColors.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if expandedSections.contains(sectionType) {
                VStack(spacing: DS.space8) {
                    ForEach(items(for: sectionType).indices, id: \.self) { index in
                        draftRow(sectionType, index: index)
                    }
                }
                .padding(.bottom, DS.space8)
            }
        }
        .padding(.horizontal, DS.space10)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes kept on the draft")
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textTertiary)
            ForEach(candidate.proposedNotes) { note in
                Text(note.body)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DS.space10)
        .padding(.vertical, DS.space8)
    }

    private func draftRow(_ sectionType: ConnectionSectionType, index: Int) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CosmoColors.textTertiary)
                .padding(.top, 8)
                .accessibilityLabel("Drag handle")
            TextEditor(text: itemBodyBinding(sectionType, index: index))
                .font(CosmoTypography.bodySmall)
                .foregroundStyle(CosmoColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 44)
            VStack(spacing: 4) {
                Button {
                    moveItem(sectionType, from: index, delta: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                Button {
                    moveItem(sectionType, from: index, delta: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index >= items(for: sectionType).count - 1)
                Button(role: .destructive) {
                    removeItem(sectionType, index: index)
                } label: {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CosmoColors.textSecondary)
            .padding(.top, 4)
        }
        .padding(8)
        .background(DS.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { candidate.proposedTitle },
            set: {
                candidate.proposedTitle = $0
                candidate.name = $0
            }
        )
    }

    private var skippedBinding: Binding<Bool> {
        Binding(
            get: { !candidate.accepted },
            set: { candidate.accepted = !$0 }
        )
    }

    private var filledSections: [ConnectionSectionType] {
        ConnectionSectionType.allCases
            .filter { !(candidate.proposedSections[$0] ?? []).isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func items(for sectionType: ConnectionSectionType) -> [ConnectionSectionItemDraft] {
        candidate.proposedSections[sectionType] ?? []
    }

    private func itemBodyBinding(_ sectionType: ConnectionSectionType, index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let item = candidate.proposedSections[sectionType]?[safe: index] else { return "" }
                return item.body
            },
            set: { newValue in
                guard var items = candidate.proposedSections[sectionType],
                      items.indices.contains(index) else { return }
                items[index].body = newValue
                candidate.proposedSections[sectionType] = items
            }
        )
    }

    private func removeItem(_ sectionType: ConnectionSectionType, index: Int) {
        guard var items = candidate.proposedSections[sectionType],
              items.indices.contains(index) else { return }
        items.remove(at: index)
        candidate.proposedSections[sectionType] = items
    }

    private func moveItem(_ sectionType: ConnectionSectionType, from index: Int, delta: Int) {
        guard var items = candidate.proposedSections[sectionType] else { return }
        let destination = index + delta
        guard items.indices.contains(index), items.indices.contains(destination) else { return }
        items.swapAt(index, destination)
        candidate.proposedSections[sectionType] = items
    }

    private func toggle(_ sectionType: ConnectionSectionType) {
        if expandedSections.contains(sectionType) {
            expandedSections.remove(sectionType)
        } else {
            expandedSections.insert(sectionType)
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(CosmoTypography.caption)
            .foregroundStyle(CosmoColors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DS.surface, in: Capsule())
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
