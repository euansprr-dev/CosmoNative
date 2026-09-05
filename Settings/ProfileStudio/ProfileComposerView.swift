// CosmoOS/Settings/ProfileStudio/ProfileComposerView.swift
// Inline document composers for the Profile Studio — write/paste, URL
// transcription, and library search expand in place inside the documents
// container. No stacked sheets.

import SwiftUI

// MARK: - Kind

enum ProfileComposerKind: Equatable {
    case write(category: ProfileDocumentCategory)
    case url(category: ProfileDocumentCategory)
    case library
}

// MARK: - Composer

struct ProfileComposerView: View {
    let kind: ProfileComposerKind
    let store: ProfileStudioStore
    let transcription: ProfileTranscriptionManager
    let onDismiss: () -> Void

    @State private var category: ProfileDocumentCategory = .story
    @State private var title = ""
    @State private var text = ""
    @State private var urlInput = ""
    @State private var libraryQuery = ""
    @State private var libraryResults: [Atom] = []
    @State private var librarySearchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            switch kind {
            case .write:
                categoryPicker(ProfileDocumentCategory.allCases)
                writeComposer
            case .url:
                categoryPicker([.reel, .thread, .underperformingReel, .underperformingThread])
                urlComposer
            case .library:
                libraryComposer
            }
        }
        .padding(DS.space12)
        .onAppear {
            switch kind {
            case .write(let initial), .url(let initial):
                category = initial
            case .library:
                break
            }
            isFocused = true
        }
    }

    // MARK: - Category picker

    private func categoryPicker(_ categories: [ProfileDocumentCategory]) -> some View {
        HStack(spacing: DS.space4) {
            ForEach(categories, id: \.self) { item in
                categoryPill(item)
            }
            Spacer(minLength: 0)
        }
    }

    private func categoryPill(_ item: ProfileDocumentCategory) -> some View {
        let isSelected = category == item
        return Button {
            withAnimation(ProMotionSprings.snappy) { category = item }
        } label: {
            Text(item.displayName)
                .font(DS.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? DS.accent : DS.textMuted)
                .padding(.horizontal, DS.space8)
                .padding(.vertical, DS.space4)
                .background(isSelected ? AnyShapeStyle(DS.accentSoft) : AnyShapeStyle(Color.clear), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? DS.accent.opacity(0.3) : DS.glassBorder, lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Write / paste

    private var writeComposer: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .padding(DS.space8)
                .dsGlassInput()
                .focused($isFocused)

            TextEditor(text: $text)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 220)
                .padding(DS.space8)
                .dsGlassInput()
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write or paste the document…")
                            .font(DS.callout)
                            .foregroundStyle(DS.textMuted)
                            .padding(.horizontal, DS.space12)
                            .padding(.vertical, DS.space12)
                            .allowsHitTesting(false)
                    }
                }

            composerFooter(
                confirmLabel: "Add document",
                confirmEnabled: !text.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                store.addDocument(ProfileDocument(
                    category: category,
                    title: title.trimmingCharacters(in: .whitespaces).isEmpty
                        ? String(text.prefix(60))
                        : title.trimmingCharacters(in: .whitespaces),
                    content: text,
                    platform: category.platformTag
                ))
                onDismiss()
            }
        }
    }

    // MARK: - URL

    private var urlComposer: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Paste an Instagram URL — it's transcribed with the same engine as the swipe file.")
                .font(DS.footnote)
                .foregroundStyle(DS.textMuted)

            HStack(spacing: DS.space8) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
                TextField("https://www.instagram.com/reel/…", text: $urlInput)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .focused($isFocused)
                    .onSubmit { submitURL() }
            }
            .padding(DS.space8)
            .dsGlassInput(isFocused: isFocused)

            composerFooter(confirmLabel: "Transcribe", confirmEnabled: isValidInstagramURL) {
                submitURL()
            }
        }
    }

    private var isValidInstagramURL: Bool {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return false }
        return host.contains("instagram.com")
    }

    private func submitURL() {
        let urlString = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidInstagramURL, let url = URL(string: urlString) else { return }

        let docId = UUID()
        withAnimation(ProMotionSprings.cardEntrance) {
            store.addDocument(ProfileDocument(
                id: docId,
                category: category,
                title: "Transcribing...",
                content: "",
                platform: category.platformTag,
                sourceURL: urlString
            ))
        }
        let targetCategory = category
        onDismiss()

        Task {
            if let completed = await transcription.transcribe(
                url: url, documentId: docId, category: targetCategory
            ) {
                store.replaceDocument(id: docId, with: completed)
            }
        }
    }

    // MARK: - Library

    private var libraryComposer: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
                TextField("Search notes, documents, ideas…", text: $libraryQuery)
                    .textFieldStyle(.plain)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .focused($isFocused)
            }
            .padding(DS.space8)
            .dsGlassInput(isFocused: isFocused)
            .onChange(of: libraryQuery) { _, newValue in
                scheduleLibrarySearch(newValue)
            }

            if libraryResults.isEmpty && !libraryQuery.isEmpty {
                Text("Nothing matched — try a title or a phrase from the document.")
                    .font(DS.footnote)
                    .foregroundStyle(DS.textMuted)
                    .padding(.vertical, DS.space8)
            } else {
                ForEach(libraryResults, id: \.uuid) { atom in
                    libraryResultRow(atom)
                }
            }

            composerFooter(confirmLabel: nil, confirmEnabled: false) {}
        }
    }

    private func scheduleLibrarySearch(_ query: String) {
        librarySearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            libraryResults = []
            return
        }
        librarySearchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = (try? await AtomRepository.shared.search(
                query: trimmed,
                types: [.note, .content, .idea, .research]
            )) ?? []
            guard !Task.isCancelled else { return }
            libraryResults = Array(results.prefix(8))
        }
    }

    private func libraryResultRow(_ atom: Atom) -> some View {
        Button {
            addLibraryDocument(atom)
        } label: {
            HStack(spacing: DS.space10) {
                Image(cosmo: atom.cosmoIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(atom.title ?? "Untitled")
                        .font(DS.callout)
                        .foregroundStyle(DS.text)
                        .lineLimit(1)
                    Text(atom.type.displayName)
                        .font(DS.footnote)
                        .foregroundStyle(DS.textMuted)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.accent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, DS.space6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add as profile context")
        .accessibilityLabel("Add \(atom.title ?? "untitled") as profile context")
    }

    private func addLibraryDocument(_ atom: Atom) {
        let content = [atom.title, atom.body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !content.isEmpty else { return }
        withAnimation(ProMotionSprings.cardEntrance) {
            store.addDocument(ProfileDocument(
                category: .voiceGuide,
                title: atom.title ?? "Library document",
                content: content,
                sourceAtomUUID: atom.uuid
            ))
        }
        onDismiss()
    }

    // MARK: - Footer

    @ViewBuilder
    private func composerFooter(confirmLabel: String?, confirmEnabled: Bool, onConfirm: @escaping () -> Void) -> some View {
        HStack {
            Button("Cancel") { onDismiss() }
                .font(DS.caption)
                .buttonStyle(.plain)
                .foregroundStyle(DS.textSecondary)
                .keyboardShortcut(.cancelAction)
                .help("Close composer (Esc)")
            Spacer()
            if let confirmLabel {
                Button(action: onConfirm) {
                    Text(confirmLabel)
                        .font(DS.caption.weight(.semibold))
                        .foregroundStyle(confirmEnabled ? DS.textOnAccent : DS.textMuted)
                        .padding(.horizontal, DS.space16)
                        .padding(.vertical, DS.space6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(confirmEnabled ? AnyShapeStyle(DS.accent) : AnyShapeStyle(DS.glassSectionFill))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!confirmEnabled)
                .keyboardShortcut(.return, modifiers: .command)
                .help("\(confirmLabel) (⌘↩)")
            }
        }
    }
}
