import AppKit
import SwiftUI

struct SpaceWorkspaceSources: View {
    let spaceID: String
    let add: () -> Void
    let open: (Atom) -> Void
    @State private var originals: [String: Atom] = [:]
    @State private var editing: SpaceCompositionReference?
    @State private var error: String?
    @State private var pdfLocation: SpaceReferencePDFLocation?
    private var store: SpaceWorkspaceStore { .shared }
    private var target: Atom? { store.sourceTarget(in: spaceID) }
    private var references: [SpaceCompositionReference] { target?.spaceComposition?.references ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.space12) {
                VStack(alignment: .leading, spacing: DS.space6) {
                    Text("References").font(DS.headline).foregroundStyle(DS.text)
                    Text(target?.title ?? "Select a page").font(DS.caption).foregroundStyle(DS.textMuted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button(action: add) { Image(systemName: "plus").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).foregroundStyle(DS.accent).disabled(target == nil).help("Attach a reference")
            }.padding(DS.space20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space24) {
                    if let origin = target?.spaceComposition?.origin {
                        VStack(alignment: .leading, spacing: DS.space6) {
                            Label("Adapted from", systemImage: "arrow.triangle.branch").font(DS.caption).foregroundStyle(DS.textMuted)
                            Button(origin.sourceTitle ?? "Original page") {
                                Task {
                                    do {
                                        guard let atom = try await AtomRepository.shared.fetch(uuid: origin.sourceUUID), !atom.isDeleted else { throw SpaceCompositionError.notFound }
                                        open(atom)
                                    } catch { self.error = error.localizedDescription }
                                }
                            }.buttonStyle(.plain).font(DS.callout).foregroundStyle(DS.accent)
                        }
                    }
                    if references.isEmpty {
                        VStack(alignment: .leading, spacing: DS.space12) {
                            Image(systemName: "link").font(DS.title2).foregroundStyle(DS.textMuted)
                            Text("Keep the source close").font(DS.callout.weight(.medium)).foregroundStyle(DS.text)
                            Text("Attach a source, save the useful passage, and add why it matters here.")
                                .font(DS.callout).foregroundStyle(DS.textSecondary)
                            Button("Attach reference…", action: add).buttonStyle(.plain).foregroundStyle(DS.accent).frame(minHeight: 44)
                        }.padding(.top, DS.space16)
                    }
                    ForEach(references) { reference in referenceView(reference) }
                    if let error { Text(error).font(DS.caption).foregroundStyle(DS.textSecondary) }
                }.padding(.horizontal, DS.space20).padding(.bottom, DS.space24)
            }
        }.background(DS.surface)
        .task(id: references.map { $0.sourceUUID }.joined(separator: ",")) { await loadOriginals() }
        .sheet(item: $editing) { reference in
            if let target { SpaceReferenceEditor(spaceID: spaceID, targetID: target.uuid, reference: reference) }
        }
        .sheet(item: $pdfLocation) { location in SpaceReferencePDFReader(location: location) }
    }
    private func referenceView(_ reference: SpaceCompositionReference) -> some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            HStack(alignment: .top, spacing: DS.space8) {
                Image(systemName: "doc.text").font(DS.callout).foregroundStyle(DS.textMuted)
                Button { openSource(reference) } label: {
                    Text(reference.sourceTitle ?? originals[reference.sourceUUID]?.title ?? "Source")
                        .font(DS.callout.weight(.medium)).multilineTextAlignment(.leading).foregroundStyle(DS.text)
                }.buttonStyle(.plain).help("Open original source")
                Spacer(minLength: 0)
                Menu {
                    Button("Edit excerpt and note…", systemImage: "square.and.pencil") { editing = reference }
                    Button("Open original", systemImage: "arrow.up.right") { openSource(reference) }
                    Divider()
                    Button("Remove reference", systemImage: "link.badge.plus") {
                        guard let target else { return }
                        store.perform(in: spaceID) { try await SpaceCompositionService.removeReference(reference.id, from: target.uuid) }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Reference actions")
            }
            if let excerpt = reference.excerpt, !excerpt.isEmpty {
                HStack(alignment: .top, spacing: DS.space12) {
                    RoundedRectangle(cornerRadius: 1).fill(DS.accent.opacity(0.35)).frame(width: 2)
                    Text(excerpt).font(DS.callout).foregroundStyle(DS.textSecondary).textSelection(.enabled)
                }.fixedSize(horizontal: false, vertical: true)
            }
            if let annotation = reference.annotation, !annotation.isEmpty {
                Text(annotation).font(DS.callout).foregroundStyle(DS.textSecondary).textSelection(.enabled)
            }
            if let anchor = reference.anchor {
                HStack(spacing: DS.space8) {
                    if let page = anchor.pageIndex { Text("Page \(page + 1)") }
                    if let seconds = anchor.timeSeconds { Text("\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))") }
                    if anchor.blockUUID != nil { Text("Saved passage") }
                }.font(DS.caption).foregroundStyle(DS.textMuted)
            }
            if originals[reference.sourceUUID] == nil {
                Text("Original unavailable · saved context kept").font(DS.caption).foregroundStyle(DS.textMuted)
            }
            if reference.excerpt?.isEmpty != false && reference.annotation?.isEmpty != false {
                Button("Add an excerpt or note…") { editing = reference }
                    .buttonStyle(.plain).font(DS.caption).foregroundStyle(DS.accent).frame(minHeight: 32)
            }
            Divider().overlay(DS.borderSubtle)
        }
    }
    private func loadOriginals() async {
        do {
            let atoms = try await AtomRepository.shared.fetchBatch(uuids: Array(Set(references.map(\.sourceUUID))))
            try Task.checkCancellation()
            originals = Dictionary(uniqueKeysWithValues: atoms.filter { !$0.isDeleted }.map { ($0.uuid, $0) }); error = nil
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
    private func openSource(_ reference: SpaceCompositionReference) {
        if let string = reference.anchor?.url, let url = URL(string: string), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        } else if let atom = originals[reference.sourceUUID] {
            if let pageIndex = reference.anchor?.pageIndex, atom.filePortalMetadata?.portalKind == .pdf {
                Task { @MainActor in
                    switch await FilePortalResolver.resolve(entityUuid: atom.uuid) {
                    case .resolved(let file):
                        if let url = file.fileURL { pdfLocation = .init(title: atom.title ?? "Source", url: url, pageIndex: pageIndex) }
                        else { error = "The PDF needs to finish downloading before this page can open." }
                    case .unavailable(let reason): error = reason
                    case .loading: error = "The PDF isn't ready yet. Try opening it again." 
                    }
                }
            } else if atom.spaceCompositionKind != nil {
                Task { @MainActor in
                    do { try await store.openOriginal(atom, from: spaceID, landingBlockID: reference.anchor?.blockUUID.flatMap(UUID.init(uuidString:))) }
                    catch { self.error = error.localizedDescription }
                }
            } else if let seconds = reference.anchor?.timeSeconds, let address = atom.researchMetadata?.url,
                      var components = URLComponents(string: address),
                      let host = components.host?.lowercased(), host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") {
                var query = components.queryItems ?? []
                query.removeAll { $0.name == "t" || $0.name == "start" }
                query.append(URLQueryItem(name: "t", value: String(Int(seconds))))
                components.queryItems = query
                if let url = components.url { NSWorkspace.shared.open(url) }
            } else { open(atom) }
        } else { error = "The original isn't available on this device. Its saved excerpt and note remain here." }
    }
}

private struct SpaceReferencePDFLocation: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let pageIndex: Int
}

private struct SpaceReferencePDFReader: View {
    let location: SpaceReferencePDFLocation
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(location.title).font(DS.headline).foregroundStyle(DS.text).lineLimit(1)
                Text("Page \(location.pageIndex + 1)").font(DS.caption).foregroundStyle(DS.textMuted)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(DS.space20)
            Divider()
            FilePortalPDFView(fileURL: location.url, initialPageIndex: location.pageIndex, onPageChanged: { _ in })
        }.frame(minWidth: 640, idealWidth: 900, minHeight: 560, idealHeight: 780).background(DS.bg)
    }
}

private struct SpaceReferenceEditor: View {
    let spaceID: String
    let targetID: String
    let reference: SpaceCompositionReference
    @Environment(\.dismiss) private var dismiss
    @State private var excerpt = ""
    @State private var annotation = ""
    @State private var page = ""
    @State private var timestamp = ""
    @State private var url = ""
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            Text(reference.sourceTitle ?? "Reference").font(DS.title2).foregroundStyle(DS.text)
            field("Saved excerpt", text: $excerpt, prompt: "Paste the useful passage…")
            field("Your note", text: $annotation, prompt: "Why does it matter here?")
            DisclosureGroup("Source location") {
                VStack(alignment: .leading, spacing: DS.space12) {
                    HStack {
                        TextField("Page number", text: $page)
                        TextField("Time (m:ss)", text: $timestamp)
                    }
                    TextField("Link to this passage", text: $url)
                }.textFieldStyle(.roundedBorder).padding(.top, DS.space12)
            }.font(DS.callout).foregroundStyle(DS.textSecondary)
            if let error { Text(error).font(DS.caption).foregroundStyle(DS.textSecondary) }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : "Save") { save() }.buttonStyle(.borderedProminent).tint(DS.accent)
                    .disabled(saving).keyboardShortcut(.defaultAction)
            }
        }.padding(DS.space32).frame(width: 560).background(DS.bg).interactiveDismissDisabled(saving)
        .onAppear {
            excerpt = reference.excerpt ?? ""; annotation = reference.annotation ?? ""; url = reference.anchor?.url ?? ""
            page = reference.anchor?.pageIndex.map { String($0 + 1) } ?? ""
            timestamp = reference.anchor?.timeSeconds.map { "\(Int($0) / 60):\(String(format: "%02d", Int($0) % 60))" } ?? ""
        }
    }
    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text(title).font(DS.caption).foregroundStyle(DS.textMuted)
            TextField(prompt, text: text, axis: .vertical).lineLimit(3...8).textFieldStyle(.plain)
                .font(DS.body).padding(DS.space12).dsGlassInput()
        }
    }
    private func save() {
        let pageValue = Int(page)
        let parts = timestamp.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
        let seconds: Double? = timestamp.isEmpty ? nil : parts.count == 2 ? parts[0].flatMap { minutes in parts[1].flatMap { second in second >= 0 && second < 60 ? minutes * 60 + second : nil } } : Double(timestamp)
        guard page.isEmpty || (pageValue ?? 0) > 0 else { error = "Enter a page number starting at 1."; return }
        guard timestamp.isEmpty || (seconds?.isFinite == true && (seconds ?? -1) >= 0) else { error = "Enter a time such as 2:30."; return }
        guard url.isEmpty || URL(string: url).map({ ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil }) == true else { error = "Enter a complete web link."; return }
        var updated = reference
        updated.excerpt = excerpt.isEmpty ? nil : excerpt; updated.annotation = annotation.isEmpty ? nil : annotation
        updated.anchor = .init(blockUUID: reference.anchor?.blockUUID, pageIndex: pageValue.map { $0 - 1 }, timeSeconds: seconds, url: url.isEmpty ? nil : url)
        saving = true
        Task { @MainActor in
            defer { saving = false }
            do {
                try await SpaceCompositionService.updateReference(updated, in: targetID)
                await SpaceWorkspaceStore.shared.load(spaceID); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
