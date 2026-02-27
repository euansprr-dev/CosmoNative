// CosmoOS/Canvas/DistillationPreviewView.swift
// Side-by-side 4-column view for previewing/editing distillation layers
// February 2026 - Thinking Lab WP3

import SwiftUI

struct DistillationPreviewView: View {
    let atom: Atom
    @StateObject private var engine = DistillationEngine.shared
    @State private var layers: DistillationLayers
    @State private var isGenerating = false

    init(atom: Atom) {
        self.atom = atom
        _layers = State(initialValue: atom.distillationLayers ?? DistillationLayers())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.accent)
                Text("Distillation Layers")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.text)
                Spacer()
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().background(DS.border)

            // 4-column grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    columnView(
                        title: "Full",
                        icon: "doc.text",
                        content: atom.body ?? atom.title ?? "",
                        isEditable: false,
                        layerKey: nil
                    )

                    columnView(
                        title: "Summary",
                        icon: "text.alignleft",
                        content: layers.summary ?? "",
                        isEditable: true,
                        layerKey: "summary"
                    )

                    columnView(
                        title: "Essence",
                        icon: "sparkle",
                        content: layers.essence ?? "",
                        isEditable: true,
                        layerKey: "essence"
                    )

                    columnView(
                        title: "Glyph",
                        icon: "textformat.size.smaller",
                        content: layers.glyph ?? "",
                        isEditable: true,
                        layerKey: "glyph"
                    )
                }
                .padding(20)
            }
        }
        .background(DS.surface)
    }

    // MARK: - Column View

    @ViewBuilder
    private func columnView(title: String, icon: String, content: String, isEditable: Bool, layerKey: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Column header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.accent)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DS.textSecondary)
                    .tracking(0.8)

                Spacer()

                if let key = layerKey, !layers.userOwnedFlags.contains(key) {
                    Button {
                        Task { await regenerate(layerKey: key) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Regenerate")
                }

                if let key = layerKey, layers.userOwnedFlags.contains(key) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DS.accent.opacity(0.6))
                        .help("Manually edited")
                }
            }

            // Content
            if isEditable, let key = layerKey {
                editableContent(key: key, content: content)
            } else {
                Text(content.isEmpty ? "No content" : content)
                    .font(.system(size: 12))
                    .foregroundColor(content.isEmpty ? DS.textMuted : DS.text)
                    .lineLimit(nil)
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func editableContent(key: String, content: String) -> some View {
        let binding = Binding<String>(
            get: {
                switch key {
                case "summary": return layers.summary ?? ""
                case "essence": return layers.essence ?? ""
                case "glyph": return layers.glyph ?? ""
                default: return ""
                }
            },
            set: { newValue in
                switch key {
                case "summary": layers.summary = newValue
                case "essence": layers.essence = newValue
                case "glyph": layers.glyph = newValue
                default: break
                }
                // Mark as user-owned when edited
                layers.userOwnedFlags.insert(key)
                saveDebounced()
            }
        )

        if content.isEmpty {
            VStack(spacing: 8) {
                Text("Not generated yet")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                Button("Generate") {
                    Task { await regenerate(layerKey: key) }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.accent)
                .buttonStyle(.plain)
            }
        } else {
            TextEditor(text: binding)
                .font(.system(size: 12))
                .foregroundColor(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60)
        }
    }

    // MARK: - Actions

    @State private var saveTask: Task<Void, Never>?

    private func saveDebounced() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            engine.layersCache[atom.uuid] = layers
            _ = try? await AtomRepository.shared.update(uuid: atom.uuid) { a in
                a.distillationLayers = layers
            }
        }
    }

    private func regenerate(layerKey: String) async {
        isGenerating = true
        defer { isGenerating = false }

        let layer: DistillationLayer
        switch layerKey {
        case "summary": layer = .summary
        case "essence": layer = .essence
        case "glyph": layer = .glyph
        default: return
        }

        await engine.regenerateLayer(layer, for: atom)
        if let updated = engine.layers(for: atom) {
            layers = updated
        }
    }
}
