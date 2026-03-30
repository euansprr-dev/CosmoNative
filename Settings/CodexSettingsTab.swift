// CosmoOS/Settings/CodexSettingsTab.swift
// Content Physics Codex — View and generate the codex from the swipe library
// Calls cloud API endpoint POST /api/codex/generate

import SwiftUI

@Observable
final class CodexViewModel {
    var codexText: String = ""
    var isGenerating = false
    var progress: String = ""
    var lastGenerated: String = ""
    var error: String?
    var extractionStats: ExtractionStats?

    struct ExtractionStats {
        let total: Int
        let extracted: Int
        let skipped: Int
        let failed: Int
    }

    func loadExistingCodex() async {
        // Look for existing codex atom in GRDB
        do {
            let atoms = try await AtomRepository.shared.fetchAll(type: .research)
            if let codexAtom = atoms.first(where: { $0.metadataDict?["isCodex"] as? Bool == true }) {
                codexText = codexAtom.body ?? ""
                lastGenerated = codexAtom.metadataDict?["updatedAt"] as? String ?? codexAtom.updatedAt
            }
        } catch {
            print("Failed to load codex: \(error)")
        }
    }

    private static let cloudBaseURL = "https://cosmonative-production.up.railway.app"

    func generateCodex(reExtractAll: Bool = false) async {
        isGenerating = true
        progress = reExtractAll ? "Re-extracting all swipes with Opus 4.6..." : "Extracting unanalyzed swipes with Opus 4.6..."
        error = nil

        do {
            print("🔬 Codex: Starting generation (reExtractAll: \(reExtractAll))")
            let apiKey = APIKeys.supabaseServiceRoleKey
            print("🔬 Codex: API key found, calling \(Self.cloudBaseURL)/api/writing/codex/generate")

            let url = URL(string: "\(Self.cloudBaseURL)/api/writing/codex/generate")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["reExtractAll": reExtractAll])
            request.timeoutInterval = 1800 // 30 min timeout for batch extraction

            let (data, response) = try await URLSession.shared.data(for: request)

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            print("🔬 Codex: Response status \(statusCode), body: \(responseBody.prefix(300))")

            guard statusCode == 200 else {
                error = "Server error (\(statusCode)): \(responseBody.prefix(200))"
                isGenerating = false
                return
            }

            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let extraction = result?["extraction"] as? [String: Any] {
                extractionStats = ExtractionStats(
                    total: extraction["total"] as? Int ?? 0,
                    extracted: extraction["extracted"] as? Int ?? 0,
                    skipped: extraction["skipped"] as? Int ?? 0,
                    failed: extraction["failed"] as? Int ?? 0
                )
            }

            progress = "Codex generated. Refreshing..."

            // Reload the codex from the database (it was saved as an atom by the cloud)
            try? await Task.sleep(for: .seconds(2))
            await loadExistingCodex()
            lastGenerated = Date().formatted(date: .abbreviated, time: .shortened)

        } catch {
            self.error = error.localizedDescription
        }

        isGenerating = false
        progress = ""
    }
}

struct CodexSettingsTab: View {
    @State private var viewModel = CodexViewModel()
    @State private var showReExtractConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerSection
            if viewModel.isGenerating {
                generatingSection
            } else if viewModel.codexText.isEmpty {
                emptySection
            } else {
                codexDisplaySection
            }
            Spacer()
        }
        .task {
            await viewModel.loadExistingCodex()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "atom")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.accent)

                Text("Content Physics Codex")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.text)

                Spacer()

                if !viewModel.codexText.isEmpty {
                    lastGeneratedBadge
                }
            }

            Text("Statistical laws of virality derived from deep quark analysis of your entire swipe library. Generated by Opus 4.6.")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private var lastGeneratedBadge: some View {
        if !viewModel.lastGenerated.isEmpty {
            Text("Last generated: \(viewModel.lastGenerated)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Generating

    @ViewBuilder
    private var generatingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(viewModel.progress)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.text)

            Text("This may take several minutes for large libraries. Each swipe is deeply analyzed by Opus 4.6.")
                .font(.system(size: 11))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptySection: some View {
        VStack(spacing: 16) {
            Image(systemName: "atom")
                .font(.system(size: 32))
                .foregroundStyle(DS.textMuted)

            Text("No Codex Generated Yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.text)

            Text("Generate your Content Physics Codex to discover the statistical laws of virality from your swipe library. Each swipe will be deeply analyzed by Opus 4.6 (~$0.03-0.05 per swipe).")
                .font(.system(size: 12))
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if let error = viewModel.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            generateButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Codex Display

    @ViewBuilder
    private var codexDisplaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                generateButton

                Button {
                    showReExtractConfirmation = true
                } label: {
                    Label("Re-extract All", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
                .confirmationDialog("Re-extract all swipes?", isPresented: $showReExtractConfirmation) {
                    Button("Re-extract All (~$3-5)", role: .destructive) {
                        Task { await viewModel.generateCodex(reExtractAll: true) }
                    }
                } message: {
                    Text("This will re-analyze every swipe with Opus 4.6, even those already extracted. Cost: ~$0.03-0.05 per swipe.")
                }

                if let stats = viewModel.extractionStats {
                    statsBadge(stats)
                }

                Spacer()
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.red)
            }

            codexScrollView
        }
    }

    @ViewBuilder
    private var codexScrollView: some View {
        ScrollView {
            Text(viewModel.codexText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Components

    @ViewBuilder
    private var generateButton: some View {
        Button {
            Task { await viewModel.generateCodex() }
        } label: {
            Label("Generate Codex", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .foregroundStyle(.white)
        .background(DS.accent, in: RoundedRectangle(cornerRadius: 8))
        .disabled(viewModel.isGenerating)
    }

    @ViewBuilder
    private func statsBadge(_ stats: CodexViewModel.ExtractionStats) -> some View {
        HStack(spacing: 8) {
            statItem("Extracted", value: "\(stats.extracted)", color: DS.green)
            statItem("Skipped", value: "\(stats.skipped)", color: DS.textMuted)
            if stats.failed > 0 {
                statItem("Failed", value: "\(stats.failed)", color: DS.red)
            }
        }
        .font(.system(size: 10, weight: .medium))
    }

    @ViewBuilder
    private func statItem(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(value) \(label)")
                .foregroundStyle(DS.textMuted)
        }
    }
}
