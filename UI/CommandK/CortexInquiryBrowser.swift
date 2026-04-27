// CosmoOS/UI/CommandK/CortexInquiryBrowser.swift
// CMD+K Inquiry tab — actions + Deep Dive list + global inquiry-scoped commands.
// Plan §16.

import SwiftUI

@MainActor
struct CortexInquiryBrowser: View {
    @ObservedObject var viewModel: CommandKViewModel

    @State private var deepDives: [Atom] = []
    @State private var showingNewDeepDiveSheet = false
    @State private var newDeepDiveTitle: String = ""
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                actionsSection
                deepDivesSection
                Spacer(minLength: DS.space24)
            }
            .padding(.horizontal, DS.space20)
            .padding(.vertical, DS.space16)
        }
        .task { await load() }
        .sheet(isPresented: $showingNewDeepDiveSheet) {
            newDeepDiveSheet
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            sectionLabel("ACTIONS")
            actionRow(icon: "plus.circle.fill", title: "New Deep Dive", shortcut: "⌘⇧D") {
                showingNewDeepDiveSheet = true
            }
            actionRow(icon: "rectangle.split.3x1.fill", title: "Start Inquiry on…", shortcut: nil) {
                // V1: pick first available Deep Dive — full picker UI is V1.1.
                if let dd = deepDives.first {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Inquiry.startInquiry,
                        object: nil,
                        userInfo: [
                            "anchorUUID": dd.uuid,
                            "anchorType": AtomType.deepDive.rawValue
                        ]
                    )
                }
            }
        }
    }

    private func actionRow(icon: String, title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.space10) {
                Image(systemName: icon)
                    .font(DS.callout)
                    .foregroundStyle(DS.accent)
                    .frame(width: 18)
                Text(title)
                    .font(DS.body)
                    .foregroundStyle(DS.text)
                Spacer()
                if let s = shortcut {
                    Text(s)
                        .font(DS.caption)
                        .foregroundStyle(DS.textMuted)
                }
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(DS.surfaceHover.opacity(0.0001), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .contentShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // SwiftUI's button hover state handles styling implicitly.
            _ = hovering
        }
    }

    // MARK: - Deep Dives

    private var deepDivesSection: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack {
                sectionLabel("DEEP DIVES (\(deepDives.count))")
                Spacer()
            }
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, DS.space8)
            } else if deepDives.isEmpty {
                Text("No Deep Dives yet — click New Deep Dive to start your first.")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
                    .padding(.vertical, DS.space12)
            } else {
                ForEach(deepDives, id: \.uuid) { dd in
                    deepDiveRow(dd)
                }
            }
        }
    }

    private func deepDiveRow(_ dd: Atom) -> some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.openDeepDive,
                object: nil,
                userInfo: ["uuid": dd.uuid]
            )
        } label: {
            HStack(spacing: DS.space10) {
                Image(systemName: "circle.hexagongrid.circle.fill")
                    .foregroundStyle(CosmoMentionColors.color(for: .deepDive))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dd.title ?? "Untitled Deep Dive")
                        .font(DS.body)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    if let maturity = dd.deepDiveMetadata?.maturity {
                        Text(maturity.displayName)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                    }
                }
                Spacer()
                Button("Start Inquiry") {
                    NotificationCenter.default.post(
                        name: CosmoNotification.Inquiry.startInquiry,
                        object: nil,
                        userInfo: [
                            "anchorUUID": dd.uuid,
                            "anchorType": AtomType.deepDive.rawValue
                        ]
                    )
                }
                .buttonStyle(.plain)
                .font(DS.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(DS.accent.opacity(0.55), lineWidth: 1))
                .foregroundStyle(DS.accent)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space8)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Deep Dive sheet

    private var newDeepDiveSheet: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("New Deep Dive")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(DS.text)
            Text("Topic name (e.g., Breathwork, What is life?, CO2 tolerance)")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
            TextField("Topic", text: $newDeepDiveTitle)
                .textFieldStyle(.plain)
                .font(DS.body)
                .padding(DS.space10)
                .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.borderSubtle, lineWidth: 1)
                )
                .onSubmit { Task { await createDeepDive() } }

            HStack {
                Button("Cancel") { showingNewDeepDiveSheet = false; newDeepDiveTitle = "" }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Button("Create") { Task { await createDeepDive() } }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, 6)
                    .background(DS.accent, in: Capsule())
                    .foregroundStyle(DS.textOnAccent)
                    .disabled(newDeepDiveTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DS.space24)
        .frame(width: 420)
    }

    private func createDeepDive() async {
        let title = newDeepDiveTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            let dd = try await InquiryRepository.shared.createDeepDive(title: title)
            await DeepDiveAliasRegistry.shared.refresh()
            showingNewDeepDiveSheet = false
            newDeepDiveTitle = ""
            await load()
            NotificationCenter.default.post(
                name: CosmoNotification.Inquiry.openDeepDive,
                object: nil,
                userInfo: ["uuid": dd.uuid]
            )
        } catch {
            print("[CortexInquiryBrowser] createDeepDive failed: \(error)")
        }
    }

    // MARK: - Loading

    private func load() async {
        let list = (try? await InquiryRepository.shared.fetchAllDeepDives()) ?? []
        deepDives = list
        isLoading = false
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.smallCaps)
            .tracking(2)
            .foregroundStyle(DS.textSecondary.opacity(0.78))
    }
}
