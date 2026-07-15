// CosmoOS/UI/FocusMode/SwipeStudy/TaxonomyManagementView.swift
// Taxonomy dimension management — view, create, reorder, and archive taxonomy values
// February 2026

import SwiftUI

// MARK: - TaxonomyManagementView

struct TaxonomyManagementView: View {
    @Environment(\.dismiss) private var dismiss

    var onClose: (() -> Void)? = nil

    @State private var selectedDimension: TaxonomyDimension = .narrative
    @State private var dimensionValues: [TaxonomyValueRow] = []
    @State private var isLoading = false
    @State private var newValueText = ""
    @State private var showAddField = false
    @State private var renamingRowID: String?
    @State private var renameText = ""

    private let gold = DS.entitySwipe

    private func performClose() {
        if let onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(DS.borderSubtle)
            dimensionPicker
            Divider().background(DS.borderSubtle)
            valuesList
        }
        .onAppear { loadValues() }
        .onChange(of: selectedDimension) { _, _ in loadValues() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Taxonomy Management")
                    .font(DS.title2)
                    .foregroundStyle(DS.text)
                Text("Manage classification values for swipe intelligence")
                    .font(DS.subheadline)
                    .foregroundStyle(DS.textMuted)
            }

            Spacer()

            Button {
                performClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Dimension Picker

    private var dimensionPicker: some View {
        HStack(spacing: 8) {
            ForEach(TaxonomyDimension.allCases, id: \.rawValue) { dimension in
                dimensionTab(dimension)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func dimensionTab(_ dimension: TaxonomyDimension) -> some View {
        Button {
            selectedDimension = dimension
        } label: {
            Text(dimension.displayName)
                .font(DS.buttonText)
                .foregroundStyle(selectedDimension == dimension ? DS.text : DS.textSecondary)
                .commandKToolbarChip(
                    isActive: selectedDimension == dimension,
                    activeFill: gold.opacity(0.15),
                    activeBorder: gold.opacity(0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Values List

    private var valuesList: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView().tint(DS.textSecondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(dimensionValues.enumerated()), id: \.element.id) { index, row in
                            valueRow(row, index: index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                Spacer()

                // Add new value
                addValueBar
            }
        }
    }

    private func valueRow(_ row: TaxonomyValueRow, index: Int) -> some View {
        HStack(spacing: 10) {
            // Drag handle / order indicator
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .frame(width: 20)

            // Color dot
            Circle()
                .fill(row.color)
                .frame(width: 8, height: 8)

            // Value name
            VStack(alignment: .leading, spacing: 1) {
                if renamingRowID == row.id {
                    renameField(row)
                } else {
                    Text(row.displayName)
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                }

                if row.isDefault {
                    Text("Default")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.textMuted)
                } else {
                    Text("Custom")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(gold.opacity(0.5))
                }
            }

            Spacer()

            // Swipe count badge
            if row.usageCount > 0 {
                Text("\(row.usageCount)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DS.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DS.surfaceHover, in: Capsule())
            }

            // Move buttons
            if !row.isDefault {
                HStack(spacing: 2) {
                    Button {
                        moveValue(at: index, direction: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Button {
                        moveValue(at: index, direction: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == dimensionValues.count - 1)
                }

                // Archive button
                Button {
                    archiveValue(row)
                } label: {
                    Image(systemName: "archivebox")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
                .help("Archive this value")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .contextMenu {
            if selectedDimension == .niche, !row.isDefault {
                nicheContextMenu(row)
            }
        }
    }

    // MARK: - Niche rename / merge

    @ViewBuilder
    private func nicheContextMenu(_ row: TaxonomyValueRow) -> some View {
        Button("Rename…") {
            renameText = row.displayName
            renamingRowID = row.id
        }
        let targets = dimensionValues.filter { $0.id != row.id && !$0.isDefault }
        if !targets.isEmpty {
            Menu("Merge into") {
                ForEach(targets) { target in
                    Button(target.displayName) {
                        mergeNiche(source: row, into: target)
                    }
                }
            }
        }
        Divider()
        Button("Archive", role: .destructive) {
            archiveValue(row)
        }
    }

    private func renameField(_ row: TaxonomyValueRow) -> some View {
        TextField("Niche name", text: $renameText)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .onSubmit { commitRename(row) }
            .onExitCommand {
                renamingRowID = nil
                renameText = ""
            }
    }

    /// Rename routes through NicheRegistry so the old value becomes an alias
    /// and every swipe carrying it is rewritten.
    private func commitRename(_ row: TaxonomyValueRow) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renamingRowID = nil
        renameText = ""
        guard !name.isEmpty, name != row.displayName, let uuid = row.atomUUID else { return }
        Task {
            await NicheRegistry.shared.rename(atomUUID: uuid, to: name)
            loadValues()
        }
    }

    /// Merge folds aliases + usage into the target, tombstones the source,
    /// and rewrites affected swipes (all inside NicheRegistry.merge).
    private func mergeNiche(source: TaxonomyValueRow, into target: TaxonomyValueRow) {
        guard let sourceUUID = source.atomUUID, let targetUUID = target.atomUUID else { return }
        Task {
            await NicheRegistry.shared.merge(sourceUUID: sourceUUID, intoUUID: targetUUID)
            loadValues()
        }
    }

    private var addValueBar: some View {
        HStack(spacing: 8) {
            if showAddField {
                TextField("New value name", text: $newValueText)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                    .onSubmit { addNewValue() }

                Button {
                    addNewValue()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(gold)
                }
                .buttonStyle(.plain)
                .disabled(newValueText.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    showAddField = false
                    newValueText = ""
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.textMuted)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showAddField = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add Custom Value")
                            .font(DS.buttonText)
                    }
                    .foregroundStyle(gold.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(gold.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(16)
    }

    // MARK: - Data Loading

    private func loadValues() {
        isLoading = true
        Task {
            var rows: [TaxonomyValueRow] = []

            // Add default enum values
            switch selectedDimension {
            case .narrative:
                rows = NarrativeStyle.allCases.enumerated().map { index, style in
                    TaxonomyValueRow(
                        id: style.rawValue,
                        displayName: style.displayName,
                        rawValue: style.rawValue,
                        color: style.color,
                        isDefault: true,
                        sortOrder: index,
                        usageCount: 0
                    )
                }
            case .contentFormat:
                rows = ContentFormat.allCases.enumerated().map { index, format in
                    TaxonomyValueRow(
                        id: format.rawValue,
                        displayName: format.displayName,
                        rawValue: format.rawValue,
                        color: format.color,
                        isDefault: true,
                        sortOrder: index,
                        usageCount: 0
                    )
                }
            case .niche:
                // Niches are free-form, load from taxonomy_value atoms
                rows = []
            case .hookType:
                rows = SwipeHookType.allCases.enumerated().map { index, hook in
                    TaxonomyValueRow(
                        id: hook.rawValue,
                        displayName: hook.displayName,
                        rawValue: hook.rawValue,
                        color: hook.color,
                        isDefault: true,
                        sortOrder: index,
                        usageCount: 0
                    )
                }
            }

            // Load custom taxonomy values from atoms
            if let customValues = try? await AtomRepository.shared.fetchTaxonomyValues(
                dimension: selectedDimension.rawValue
            ) {
                for atom in customValues {
                    if let meta = atom.metadataValue(as: TaxonomyValueMetadata.self) {
                        rows.append(TaxonomyValueRow(
                            id: atom.uuid,
                            displayName: meta.value,
                            rawValue: meta.value,
                            color: gold,
                            isDefault: false,
                            sortOrder: meta.sortOrder,
                            atomUUID: atom.uuid,
                            usageCount: meta.usageCount ?? 0
                        ))
                    }
                }
            }

            // Niches order by how much of the library they hold; other
            // dimensions keep their manual sortOrder.
            if selectedDimension == .niche {
                rows.sort {
                    if $0.usageCount != $1.usageCount { return $0.usageCount > $1.usageCount }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            } else {
                rows.sort { $0.sortOrder < $1.sortOrder }
            }

            dimensionValues = rows
            isLoading = false
        }
    }

    private func addNewValue() {
        let value = newValueText.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }

        Task {
            if selectedDimension == .niche {
                // Registry-routed: a typed label that matches an existing
                // niche folds into it instead of creating a twin.
                _ = await NicheRegistry.shared.seed(value: value, aliases: [], usageCount: 0)
            } else {
                _ = try? await AtomRepository.shared.createTaxonomyValue(
                    dimension: selectedDimension.rawValue,
                    value: value,
                    sortOrder: dimensionValues.count
                )
            }
            newValueText = ""
            showAddField = false
            loadValues()
        }
    }

    private func moveValue(at index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < dimensionValues.count else { return }
        dimensionValues.swapAt(index, newIndex)
        // Update sort orders
        for i in 0..<dimensionValues.count {
            dimensionValues[i].sortOrder = i
        }
    }

    private func archiveValue(_ row: TaxonomyValueRow) {
        guard let atomUUID = row.atomUUID else { return }
        Task {
            if var atom = try? await AtomRepository.shared.fetch(uuid: atomUUID) {
                atom.isDeleted = true
                _ = try? await AtomRepository.shared.update(atom)
                if selectedDimension == .niche {
                    NicheRegistry.shared.invalidate()
                }
                loadValues()
            }
        }
    }
}

// MARK: - Supporting Types

enum TaxonomyDimension: String, CaseIterable {
    case narrative
    case contentFormat
    case niche
    case hookType

    var displayName: String {
        switch self {
        case .narrative: return "Narratives"
        case .contentFormat: return "Formats"
        case .niche: return "Niches"
        case .hookType: return "Hook Types"
        }
    }
}

struct TaxonomyValueRow: Identifiable {
    let id: String
    var displayName: String
    var rawValue: String
    var color: Color
    var isDefault: Bool
    var sortOrder: Int
    var atomUUID: String?
    var usageCount: Int = 0
}
