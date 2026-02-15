// CosmoOS/UI/FocusMode/SwipeStudy/CompareCreatorsView.swift
// Side-by-side comparison of 2-3 creators
// February 2026

import SwiftUI

// MARK: - CompareCreatorsView

struct CompareCreatorsView: View {

    let availableCreators: [Atom]
    let initialSelection: [Atom]
    let onClose: () -> Void

    @State private var selectedCreators: [Atom] = []
    @State private var creatorSwipes: [String: [Atom]] = [:]
    @State private var isLoading = true
    @State private var showPicker = false
    @State private var hasAppeared = false

    private let gold = Color(hex: "#FFD700")
    private let maxCompare = 3

    init(availableCreators: [Atom], initialSelection: [Atom] = [], onClose: @escaping () -> Void) {
        self.availableCreators = availableCreators
        self.initialSelection = initialSelection
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0F").ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().background(Color.white.opacity(0.1))

                if selectedCreators.count < 2 {
                    selectionPrompt
                } else {
                    comparisonContent
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
        }
        .onAppear {
            if !initialSelection.isEmpty {
                selectedCreators = Array(initialSelection.prefix(maxCompare))
            }
            withAnimation(ProMotionSprings.snappy) { hasAppeared = true }
            loadSwipesForSelected()
        }
        .sheet(isPresented: $showPicker) {
            creatorPickerSheet
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14))
                .foregroundColor(gold)

            Text("Compare Creators")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            // Add/change creators
            if selectedCreators.count < maxCompare {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                        Text("Add Creator")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(gold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(gold.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(gold.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Selection Prompt

    private var selectionPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 48))
                .foregroundColor(gold.opacity(0.3))

            Text("Select 2-3 creators to compare")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            // Quick-select chips from available creators
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableCreators.prefix(10), id: \.uuid) { atom in
                        creatorSelectionChip(atom)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func creatorSelectionChip(_ atom: Atom) -> some View {
        let isSelected = selectedCreators.contains { $0.uuid == atom.uuid }
        Button {
            toggleCreator(atom)
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(gold.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text(initialsFor(atom.title))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(gold)
                }
                Text(atom.title ?? "Unknown")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(gold)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? gold.opacity(0.2) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? gold.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleCreator(_ atom: Atom) {
        if let idx = selectedCreators.firstIndex(where: { $0.uuid == atom.uuid }) {
            selectedCreators.remove(at: idx)
        } else if selectedCreators.count < maxCompare {
            selectedCreators.append(atom)
        }
        loadSwipesForSelected()
    }

    // MARK: - Comparison Content

    private var comparisonContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Creator header columns
                creatorHeaders

                // Dimension comparisons
                dimensionRow(title: "Avg Hook Score", icon: "chart.bar.fill") { atom in
                    let swipes = creatorSwipes[atom.uuid] ?? []
                    let scores = swipes.compactMap { $0.swipeAnalysis?.hookScore }
                    return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
                }

                dimensionRow(title: "Swipe Count", icon: "bolt.fill") { atom in
                    Double(creatorSwipes[atom.uuid]?.count ?? 0)
                }

                // Narrative style comparison
                narrativeComparison

                // Framework comparison
                frameworkComparison

                // Emotion comparison
                emotionComparison

                // Persuasion comparison
                persuasionComparison
            }
            .padding(20)
        }
    }

    // MARK: - Creator Headers

    private var creatorHeaders: some View {
        HStack(spacing: 12) {
            // Label column
            Color.clear.frame(width: 120)

            ForEach(selectedCreators, id: \.uuid) { atom in
                let meta = atom.metadataValue(as: CreatorMetadata.self)
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(gold.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text(initialsFor(atom.title))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(gold)
                    }
                    Text(atom.title ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let handle = meta?.handle {
                        Text(handle)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    // Remove button
                    Button {
                        selectedCreators.removeAll { $0.uuid == atom.uuid }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Dimension Row (numeric)

    private func dimensionRow(title: String, icon: String, value: (Atom) -> Double?) -> some View {
        let values = selectedCreators.map { value($0) }
        let maxVal = values.compactMap { $0 }.max()

        return HStack(spacing: 12) {
            // Label
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(gold)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 120, alignment: .leading)

            ForEach(Array(selectedCreators.enumerated()), id: \.element.uuid) { index, atom in
                let val = values[index]
                let isWinner = val != nil && val == maxVal && values.compactMap({ $0 }).count > 1
                VStack(spacing: 6) {
                    Text(val.map { String(format: "%.1f", $0) } ?? "--")
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                        .foregroundColor(isWinner ? gold : .white)

                    // Visual bar
                    if let val = val, let maxVal = maxVal, maxVal > 0 {
                        barView(proportion: val / maxVal, isWinner: isWinner)
                    }

                    if isWinner {
                        winnerBadge
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func barView(proportion: Double, isWinner: Bool) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(isWinner ? gold.opacity(0.6) : Color.white.opacity(0.15))
                .frame(width: geo.size.width * CGFloat(min(proportion, 1.0)), height: 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 6)
    }

    private var winnerBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 8))
            Text("Best")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(gold)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(gold.opacity(0.15), in: Capsule())
    }

    // MARK: - Narrative Comparison

    private var narrativeComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 11))
                    .foregroundColor(gold)
                Text("NARRATIVE STYLES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: 120)

                ForEach(selectedCreators, id: \.uuid) { atom in
                    let swipes = creatorSwipes[atom.uuid] ?? []
                    let narrativeCounts = Dictionary(
                        swipes.compactMap { $0.swipeAnalysis?.primaryNarrative }.map { ($0, 1) },
                        uniquingKeysWith: +
                    ).sorted { $0.value > $1.value }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(narrativeCounts.prefix(4), id: \.key) { style, count in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(style.color)
                                    .frame(width: 6, height: 6)
                                Text(style.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        if narrativeCounts.isEmpty {
                            Text("No data")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Framework Comparison

    private var frameworkComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 11))
                    .foregroundColor(gold)
                Text("FRAMEWORKS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: 120)

                ForEach(selectedCreators, id: \.uuid) { atom in
                    let swipes = creatorSwipes[atom.uuid] ?? []
                    let fwCounts = Dictionary(
                        swipes.compactMap { $0.swipeAnalysis?.frameworkType }.map { ($0, 1) },
                        uniquingKeysWith: +
                    ).sorted { $0.value > $1.value }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(fwCounts.prefix(4), id: \.key) { fw, count in
                            HStack(spacing: 4) {
                                Text(fw.abbreviation)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(fw.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(fw.color.opacity(0.15), in: Capsule())
                                Spacer()
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        if fwCounts.isEmpty {
                            Text("No data")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Emotion Comparison

    private var emotionComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundColor(gold)
                Text("EMOTIONAL PATTERNS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: 120)

                ForEach(selectedCreators, id: \.uuid) { atom in
                    let swipes = creatorSwipes[atom.uuid] ?? []
                    let emotionCounts = Dictionary(
                        swipes.compactMap { $0.swipeAnalysis?.dominantEmotion }.map { ($0, 1) },
                        uniquingKeysWith: +
                    ).sorted { $0.value > $1.value }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(emotionCounts.prefix(4), id: \.key) { emotion, count in
                            HStack(spacing: 4) {
                                Image(systemName: emotion.iconName)
                                    .font(.system(size: 9))
                                    .foregroundColor(emotion.color)
                                Text(emotion.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        if emotionCounts.isEmpty {
                            Text("No data")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Persuasion Comparison

    private var persuasionComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11))
                    .foregroundColor(gold)
                Text("PERSUASION TECHNIQUES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(alignment: .top, spacing: 12) {
                Color.clear.frame(width: 120)

                ForEach(selectedCreators, id: \.uuid) { atom in
                    let swipes = creatorSwipes[atom.uuid] ?? []
                    let allTechniques = swipes.flatMap { $0.swipeAnalysis?.persuasionTechniques ?? [] }
                    let typeCounts = Dictionary(
                        allTechniques.map { ($0.type, 1) },
                        uniquingKeysWith: +
                    ).sorted { $0.value > $1.value }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(typeCounts.prefix(5), id: \.key) { pType, count in
                            HStack(spacing: 4) {
                                Image(systemName: pType.iconName)
                                    .font(.system(size: 9))
                                    .foregroundColor(pType.color)
                                Text(pType.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        if typeCounts.isEmpty {
                            Text("No data")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#1A1A25"), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Creator Picker Sheet

    private var creatorPickerSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Select Creator")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Done") { showPicker = false }
                    .buttonStyle(.plain)
                    .foregroundColor(gold)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(availableCreators, id: \.uuid) { atom in
                        let isSelected = selectedCreators.contains { $0.uuid == atom.uuid }
                        pickerRow(atom: atom, isSelected: isSelected)
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .padding(20)
        .frame(width: 400)
        .background(Color(hex: "#0A0A0F"))
    }

    @ViewBuilder
    private func pickerRow(atom: Atom, isSelected: Bool) -> some View {
        let meta = atom.metadataValue(as: CreatorMetadata.self)
        Button {
            toggleCreator(atom)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(gold.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Text(initialsFor(atom.title))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(gold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(atom.title ?? "Unknown")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    if let handle = meta?.handle {
                        Text(handle)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                Spacer()

                if let count = meta?.swipeCount, count > 0 {
                    Text("\(count) swipes")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(gold)
                } else if selectedCreators.count >= maxCompare {
                    Image(systemName: "circle")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.15))
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? gold.opacity(0.1) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isSelected && selectedCreators.count >= maxCompare)
    }

    // MARK: - Data Loading

    private func loadSwipesForSelected() {
        Task {
            isLoading = true
            for atom in selectedCreators {
                if creatorSwipes[atom.uuid] == nil {
                    let swipes = try? await AtomRepository.shared.fetchSwipesByTaxonomy(creatorUUID: atom.uuid)
                    creatorSwipes[atom.uuid] = swipes ?? []
                }
            }
            isLoading = false
        }
    }

    // MARK: - Helpers

    private func initialsFor(_ name: String?) -> String {
        guard let name = name, !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
