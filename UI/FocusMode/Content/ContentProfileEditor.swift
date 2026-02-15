// CosmoOS/UI/FocusMode/Content/ContentProfileEditor.swift
// Profile editor for creating and managing client/brand profiles
// February 2026

import SwiftUI

// MARK: - Content Profile Editor

/// Full-form editor for ClientProfileMetadata. Used from:
/// - IdeaFocusModeView "Assign Client" dropdown (create new)
/// - Creative dimension dashboard (manage profiles)
/// - Settings (profile management)
struct ContentProfileEditor: View {
    @Environment(\.dismiss) private var dismiss

    /// If editing an existing profile, pass its atom. Nil = create new.
    let existingAtom: Atom?
    let onSave: (Atom) -> Void

    @State private var clientName: String = ""
    @State private var handle: String = ""
    @State private var niche: String = ""
    @State private var industry: String = ""
    @State private var targetAudience: String = ""
    @State private var notes: String = ""

    // Brand context
    @State private var brandStory: String = ""
    @State private var brandVision: String = ""
    @State private var coreBeliefs: [String] = []
    @State private var newBelief: String = ""
    @State private var voiceNotes: String = ""
    @State private var uniqueAngle: String = ""

    // Performance
    @State private var topPerformingTranscripts: [String] = [""]
    @State private var bestFormats: Set<String> = []

    // Posting
    @State private var postingFrequency: String = ""
    @State private var preferredPostTimes: [String] = []
    @State private var newPostTime: String = ""

    // Identity
    @State private var isPersonalBrand: Bool = true
    @State private var selectedPlatforms: Set<SocialPlatform> = []

    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider().background(Color.white.opacity(0.08))
            formContent
            Divider().background(Color.white.opacity(0.08))
            bottomBar
        }
        .frame(width: 560, height: 680)
        .background(CosmoColors.thinkspaceSecondary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear { loadExisting() }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 16))
                .foregroundColor(CosmoColors.lavender)

            Text(existingAtom == nil ? "New Profile" : "Edit Profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Form Content

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                identitySection
                brandContextSection
                performanceSection
                postingSection
            }
            .padding(20)
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Identity")

            fieldRow(label: "Name", placeholder: "Client or brand name", text: $clientName)
            fieldRow(label: "Handle", placeholder: "@handle", text: $handle)
            fieldRow(label: "Niche", placeholder: "e.g., personal finance, fitness", text: $niche)
            fieldRow(label: "Industry", placeholder: "e.g., SaaS, health & wellness", text: $industry)
            fieldRow(label: "Audience", placeholder: "Who they create for", text: $targetAudience)

            // Personal brand toggle
            HStack(spacing: 10) {
                fieldLabel("Brand Type")
                Spacer()
                Picker("", selection: $isPersonalBrand) {
                    Text("Personal").tag(true)
                    Text("Company").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            // Platform multi-select
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Platforms")
                platformChips
            }
        }
    }

    private var platformChips: some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SocialPlatform.allCases, id: \.self) { platform in
                platformChipButton(platform)
            }
        }
    }

    @ViewBuilder
    private func platformChipButton(_ platform: SocialPlatform) -> some View {
        let isSelected = selectedPlatforms.contains(platform)
        Button(action: {
            if isSelected {
                selectedPlatforms.remove(platform)
            } else {
                selectedPlatforms.insert(platform)
            }
        }) {
            platformChipLabel(platform, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func platformChipLabel(_ platform: SocialPlatform, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: platform.iconName)
                .font(.system(size: 10))
            Text(platform.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(isSelected ? .white : .white.opacity(0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? CosmoColors.lavender.opacity(0.3) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? CosmoColors.lavender.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Brand Context Section

    private var brandContextSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Brand Context")

            textAreaField(label: "Voice Notes", placeholder: "Describe the tone, style, and personality...", text: $voiceNotes)
            textAreaField(label: "Unique Angle", placeholder: "What makes this perspective different...", text: $uniqueAngle)
            textAreaField(label: "Brand Story", placeholder: "Origin story or brand narrative...", text: $brandStory)
            fieldRow(label: "Vision", placeholder: "Long-term mission or vision", text: $brandVision)

            // Core beliefs list
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Core Beliefs")
                ForEach(coreBeliefs.indices, id: \.self) { index in
                    beliefRow(index: index)
                }
                addBeliefRow
            }
        }
    }

    @ViewBuilder
    private func beliefRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Text(coreBeliefs[index])
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { coreBeliefs.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private var addBeliefRow: some View {
        HStack(spacing: 8) {
            TextField("Add a core belief...", text: $newBelief)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .onSubmit {
                    addBelief()
                }

            Button(action: { addBelief() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.lavender.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(newBelief.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Performance Context")

            // Best formats multi-select
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Best Formats")
                formatChips
            }

            // Top performing transcripts
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Top Performing Content")
                Text("Paste transcripts or text of top-performing posts for AI context")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))

                ForEach(topPerformingTranscripts.indices, id: \.self) { index in
                    transcriptField(index: index)
                }

                if topPerformingTranscripts.count < 5 {
                    Button(action: { topPerformingTranscripts.append("") }) {
                        addTranscriptButtonLabel
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var formatChips: some View {
        let formats = ContentFormat.allCases
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(formats, id: \.rawValue) { format in
                formatChipButton(format)
            }
        }
    }

    @ViewBuilder
    private func formatChipButton(_ format: ContentFormat) -> some View {
        let isSelected = bestFormats.contains(format.rawValue)
        Button(action: {
            if isSelected {
                bestFormats.remove(format.rawValue)
            } else {
                bestFormats.insert(format.rawValue)
            }
        }) {
            formatChipLabel(format, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func formatChipLabel(_ format: ContentFormat, isSelected: Bool) -> some View {
        Text(format.displayName)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CosmoColors.skyBlue.opacity(0.3) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? CosmoColors.skyBlue.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private func transcriptField(index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TextEditor(text: Binding(
                get: { index < topPerformingTranscripts.count ? topPerformingTranscripts[index] : "" },
                set: { if index < topPerformingTranscripts.count { topPerformingTranscripts[index] = $0 } }
            ))
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.8))
            .scrollContentBackground(.hidden)
            .frame(height: 60)
            .padding(8)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

            if topPerformingTranscripts.count > 1 {
                Button(action: { topPerformingTranscripts.remove(at: index) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var addTranscriptButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 10))
            Text("Add transcript")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(CosmoColors.lavender.opacity(0.7))
    }

    // MARK: - Posting Section

    private var postingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Posting Schedule")

            fieldRow(label: "Frequency", placeholder: "e.g., 3x/week, daily", text: $postingFrequency)

            // Preferred post times
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Preferred Times")
                ForEach(preferredPostTimes.indices, id: \.self) { index in
                    postTimeRow(index: index)
                }
                addPostTimeRow
            }

            textAreaField(label: "Notes", placeholder: "General notes about this client...", text: $notes)
        }
    }

    @ViewBuilder
    private func postTimeRow(index: Int) -> some View {
        HStack(spacing: 8) {
            Text(preferredPostTimes[index])
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { preferredPostTimes.remove(at: index) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private var addPostTimeRow: some View {
        HStack(spacing: 8) {
            TextField("e.g., 9:00 AM EST", text: $newPostTime)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .onSubmit { addPostTime() }

            Button(action: { addPostTime() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(CosmoColors.lavender.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(newPostTime.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if existingAtom != nil {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: { Task { await save() } }) {
                saveButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(clientName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var saveButtonLabel: some View {
        HStack(spacing: 6) {
            if isSaving {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
            }
            Text(existingAtom == nil ? "Create Profile" : "Save Changes")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(clientName.trimmingCharacters(in: .whitespaces).isEmpty
                      ? Color.white.opacity(0.08)
                      : CosmoColors.lavender)
        )
    }

    // MARK: - Shared Field Components

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.3))
            .tracking(1.2)
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            fieldLabel(label)
                .frame(width: 80, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func textAreaField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.2))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                TextEditor(text: text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .scrollContentBackground(.hidden)
                    .frame(height: 56)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Actions

    private func addBelief() {
        let trimmed = newBelief.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        coreBeliefs.append(trimmed)
        newBelief = ""
    }

    private func addPostTime() {
        let trimmed = newPostTime.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        preferredPostTimes.append(trimmed)
        newPostTime = ""
    }

    private func loadExisting() {
        guard let atom = existingAtom else { return }
        clientName = atom.title ?? ""

        // Try ClientProfileMetadata first (ContentPipelineService format)
        if let meta = atom.metadataValue(as: ClientProfileMetadata.self) {
            handle = meta.handle ?? ""
            niche = meta.niche ?? meta.industry ?? ""
            industry = meta.industry ?? ""
            targetAudience = meta.targetAudience ?? ""
            notes = meta.notes ?? ""
            brandStory = meta.brandStory ?? ""
            brandVision = meta.brandVision ?? ""
            coreBeliefs = meta.coreBeliefs ?? []
            voiceNotes = meta.voiceNotes ?? ""
            uniqueAngle = meta.uniqueAngle ?? ""
            topPerformingTranscripts = meta.topPerformingTranscripts ?? [""]
            if topPerformingTranscripts.isEmpty { topPerformingTranscripts = [""] }
            bestFormats = Set(meta.bestFormats ?? [])
            postingFrequency = meta.postingFrequency ?? ""
            preferredPostTimes = meta.preferredPostTimes ?? []
            isPersonalBrand = meta.isPersonalBrand ?? true
            selectedPlatforms = Set(meta.platforms)
        }
        // Fallback to ClientMetadata (Atom.swift format)
        else if let meta = atom.metadataValue(as: ClientMetadata.self) {
            niche = meta.niche ?? ""
            voiceNotes = meta.brandVoice ?? ""
            if let formats = meta.preferredFormats {
                bestFormats = Set(formats)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let trimmedName = clientName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Filter empty transcripts
        let transcripts = topPerformingTranscripts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let metadata = ClientProfileMetadata(
            clientId: existingAtom.flatMap { atom in
                atom.metadataValue(as: ClientProfileMetadata.self)?.clientId
            } ?? UUID().uuidString,
            clientName: trimmedName,
            platforms: Array(selectedPlatforms),
            activeStatus: true,
            notes: notes.isEmpty ? nil : notes,
            industry: industry.isEmpty ? nil : industry,
            targetAudience: targetAudience.isEmpty ? nil : targetAudience,
            brandStory: brandStory.isEmpty ? nil : brandStory,
            brandVision: brandVision.isEmpty ? nil : brandVision,
            coreBeliefs: coreBeliefs.isEmpty ? nil : coreBeliefs,
            voiceNotes: voiceNotes.isEmpty ? nil : voiceNotes,
            uniqueAngle: uniqueAngle.isEmpty ? nil : uniqueAngle,
            topPerformingTranscripts: transcripts.isEmpty ? nil : transcripts,
            bestFormats: bestFormats.isEmpty ? nil : Array(bestFormats),
            postingFrequency: postingFrequency.isEmpty ? nil : postingFrequency,
            preferredPostTimes: preferredPostTimes.isEmpty ? nil : preferredPostTimes,
            handle: handle.isEmpty ? nil : handle,
            niche: niche.isEmpty ? nil : niche,
            isPersonalBrand: isPersonalBrand
        )

        do {
            if var existing = existingAtom {
                existing.title = trimmedName
                existing.body = notes.isEmpty ? nil : notes
                existing.metadata = metadata.toJSON()
                let saved = try await AtomRepository.shared.update(existing)
                onSave(saved)
            } else {
                var atom = Atom.new(type: .clientProfile, title: trimmedName, body: notes.isEmpty ? nil : notes)
                atom.metadata = metadata.toJSON()
                let saved = try await AtomRepository.shared.create(atom)
                onSave(saved)
            }
            dismiss()
        } catch {
            print("ContentProfileEditor: Save failed: \(error.localizedDescription)")
        }
    }
}
