// CosmoOS/UI/FocusMode/SwipeStudy/TaxonomyManagementView.swift
// Taxonomy dimension management — view, create, reorder, and archive taxonomy values
// February 2026

import SwiftUI

// MARK: - TaxonomyManagementView

struct TaxonomyManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDimension: TaxonomyDimension = .narrative
    @State private var dimensionValues: [TaxonomyValueRow] = []
    @State private var isLoading = false
    @State private var newValueText = ""
    @State private var showAddField = false

    private let gold = Color(hex: "#FFD700")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.1))
            dimensionPicker
            Divider().background(Color.white.opacity(0.1))
            valuesList
        }
        .frame(width: 480, height: 520)
        .background(Color(hex: "#0A0A0F"))
        .onAppear { loadValues() }
        .onChange(of: selectedDimension) { _, _ in loadValues() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Taxonomy Management")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("Manage classification values for swipe intelligence")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.4))
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
        .background(Color(hex: "#0A0A0F"))
    }

    private func dimensionTab(_ dimension: TaxonomyDimension) -> some View {
        Button {
            selectedDimension = dimension
        } label: {
            Text(dimension.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selectedDimension == dimension ? .white : .white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedDimension == dimension ? gold.opacity(0.2) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    selectedDimension == dimension ? gold.opacity(0.5) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Values List

    private var valuesList: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView().tint(.white)
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
                .foregroundColor(.white.opacity(0.2))
                .frame(width: 20)

            // Color dot
            Circle()
                .fill(row.color)
                .frame(width: 8, height: 8)

            // Value name
            VStack(alignment: .leading, spacing: 1) {
                Text(row.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                if row.isDefault {
                    Text("Default")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                } else {
                    Text("Custom")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(gold.opacity(0.5))
                }
            }

            Spacer()

            // Swipe count badge
            if row.usageCount > 0 {
                Text("\(row.usageCount)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }

            // Move buttons
            if !row.isDefault {
                HStack(spacing: 2) {
                    Button {
                        moveValue(at: index, direction: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Button {
                        moveValue(at: index, direction: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(index == dimensionValues.count - 1)
                }

                // Archive button
                Button {
                    archiveValue(row)
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Archive this value")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
    }

    private var addValueBar: some View {
        HStack(spacing: 8) {
            if showAddField {
                TextField("New value name", text: $newValueText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { addNewValue() }

                Button {
                    addNewValue()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(gold)
                }
                .buttonStyle(.plain)
                .disabled(newValueText.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    showAddField = false
                    newValueText = ""
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
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
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(gold.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(gold.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(hex: "#0A0A0F"))
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
                            usageCount: 0
                        ))
                    }
                }
            }

            // Sort by sortOrder
            rows.sort { $0.sortOrder < $1.sortOrder }

            dimensionValues = rows
            isLoading = false
        }
    }

    private func addNewValue() {
        let value = newValueText.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }

        Task {
            let _ = try? await AtomRepository.shared.createTaxonomyValue(
                dimension: selectedDimension.rawValue,
                value: value,
                sortOrder: dimensionValues.count
            )
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
                try? await AtomRepository.shared.update(atom)
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
