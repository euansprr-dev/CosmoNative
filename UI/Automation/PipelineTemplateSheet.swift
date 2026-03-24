// CosmoOS/UI/Automation/PipelineTemplateSheet.swift
// Visual template picker — one-click workflow blueprints
// Shows template preview with cluster layout, creates on confirm

import SwiftUI

struct PipelineTemplateSheet: View {

    let origin: CGPoint
    let thinkspaceId: String?
    let clusterEngine: CanvasClusterEngine
    let blocks: [CanvasBlock]
    let onDismiss: () -> Void

    @State private var selectedTemplate: PipelineTemplate?
    @State private var clientName = ""
    @State private var clientProfiles: [Atom] = []
    @State private var selectedClientUUID: String?
    @State private var isCreating = false
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            divider
            templateGrid
            if let selected = selectedTemplate, selected.requiresClient {
                divider
                clientPicker
            }
            divider
            sheetFooter
        }
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .dsFloatingShadow()
        .scaleEffect(appeared ? 1.0 : 0.94)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.78)) {
                appeared = true
            }
            loadClients()
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.accent)

            Text("Add Pipeline")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.text)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Template Grid

    private var templateGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(PipelineTemplate.allCases) { template in
                templateCard(template)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func templateCard(_ template: PipelineTemplate) -> some View {
        let isSelected = selectedTemplate == template

        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selectedTemplate = template
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: template.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(template.accentColor)

                    Spacer()

                    Text("\(template.clusterCount)")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(DS.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DS.surfaceHover))
                }

                Text(template.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Text(template.description)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(3)
                    .lineSpacing(1)

                // Mini cluster preview
                clusterPreview(template)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? template.accentColor.opacity(0.06) : DS.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? template.accentColor.opacity(0.4) : DS.borderSubtle, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.name): \(template.description)")
    }

    private func clusterPreview(_ template: PipelineTemplate) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<template.clusterCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(CanvasCluster.palette[i % CanvasCluster.palette.count])
                    .frame(height: 12)

                if i < template.clusterCount - 1 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(DS.textMuted.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Client Picker

    private var clientPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SELECT CLIENT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.textMuted)
                .tracking(0.8)

            if clientProfiles.isEmpty {
                TextField("Client name", text: $clientName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(DS.surface))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.borderSubtle, lineWidth: 0.5))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(clientProfiles, id: \.uuid) { client in
                            clientPill(client)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func clientPill(_ client: Atom) -> some View {
        let isSelected = selectedClientUUID == client.uuid

        Button {
            selectedClientUUID = client.uuid
            clientName = client.title ?? "Client"
        } label: {
            Text(client.title ?? "Unknown")
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : DS.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? DS.accent : DS.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? DS.accent : DS.borderSubtle, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack {
            Button("Cancel") { onDismiss() }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .buttonStyle(.plain)

            Spacer()

            Button {
                materialize()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Create Pipeline")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canCreate ? DS.accent : DS.textMuted)
                )
                .shadow(color: canCreate ? DS.accent.opacity(0.2) : .clear, radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!canCreate || isCreating)
            .opacity(isCreating ? 0.6 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canCreate: Bool {
        guard let template = selectedTemplate else { return false }
        if template.requiresClient { return !clientName.isEmpty }
        return true
    }

    // MARK: - Shared

    private var divider: some View {
        Rectangle()
            .fill(DS.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    // MARK: - Data

    private func loadClients() {
        Task {
            clientProfiles = (try? await AtomRepository.shared.fetchAll(type: .clientProfile)) ?? []
        }
    }

    private func materialize() {
        guard let template = selectedTemplate else { return }
        isCreating = true

        Task {
            let _ = await PipelineTemplateMaterializer.materialize(
                template: template,
                clientUUID: selectedClientUUID,
                clientName: clientName.isEmpty ? nil : clientName,
                origin: origin,
                thinkspaceId: thinkspaceId,
                clusterEngine: clusterEngine,
                blocks: blocks
            )
            isCreating = false
            onDismiss()
        }
    }
}
