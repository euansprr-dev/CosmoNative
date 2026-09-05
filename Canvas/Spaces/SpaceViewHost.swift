// CosmoOS/Canvas/Spaces/SpaceViewHost.swift
// The non-canvas views of a space, hosted over the keep-alive canvas world.
// Materials and Inquiries mount on first visit and stay alive so switching
// preserves scroll position and avoids repeating their initial layout.
// A space switch tears down their state.
//
// Layout-inert law: the host is wrapped in a GeometryReader window and
// clipped by its mounting site — the hosted content must never
// never propose a size to the canvas ZStack.

import SwiftUI

struct SpaceViewHost<Library: View>: View {
    let thinkspaceId: String?
    let activeView: SpaceView
    let deepDiveChrome: DeepDiveStudyChromeModel
    var contentLeadingInset: CGFloat = 0
    @ViewBuilder let library: () -> Library

    @State private var hasVisitedInquiries = false
    @State private var hasVisitedMaterials = false
    @State private var preservationError: String?
    private var workspaceIsVisible: Bool {
        guard let thinkspaceId else { return false }
        return activeView == .canvas && SpaceWorkspaceStore.shared.isPresenting(in: thinkspaceId)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if hasVisitedMaterials {
                library().padding(.leading, contentLeadingInset)
                    .opacity(activeView == .library ? 1 : 0)
                    .allowsHitTesting(activeView == .library)
                    .accessibilityHidden(activeView != .library)
            }
            if hasVisitedInquiries, let thinkspaceId {
                SpaceInquiriesView(spaceID: thinkspaceId)
                    .id(thinkspaceId)
                    .padding(.leading, contentLeadingInset)
                    .opacity(activeView == .deepDive ? 1 : 0)
                    .allowsHitTesting(activeView == .deepDive)
                    .accessibilityHidden(activeView != .deepDive)
            }
            if workspaceIsVisible, let thinkspaceId {
                SpaceWorkspaceView(spaceID: thinkspaceId)
                    .padding(.leading, contentLeadingInset)
                    .background(DS.bg)
            }
            if let preservationError, activeView != .canvas {
                HStack {
                    Text(preservationError).font(DS.callout)
                    Button("Retry") { Task { await preserve() } }
                }.padding(DS.space16).background(DS.surface, in: .rect(cornerRadius: 12))
                    .padding(.top, SpaceChromeMetrics.contentTopInset + DS.space8)
            }
        }
        .background(activeView == .canvas && !workspaceIsVisible ? Color.clear : DS.bg)
        .onChange(of: activeView, initial: true) { _, view in
            if view == .deepDive { hasVisitedInquiries = true }
            if view == .library { hasVisitedMaterials = true }
            deepDiveChrome.isFrontmost = false
        }
        .onChange(of: thinkspaceId) { _, _ in hasVisitedInquiries = activeView == .deepDive; hasVisitedMaterials = activeView == .library }
        .task(id: thinkspaceId) {
            await preserve()
            if let thinkspaceId {
                await SpaceWorkspaceStore.shared.load(thinkspaceId)
                if !Task.isCancelled, SpaceWorkspaceStore.shared.isPresenting(in: thinkspaceId) {
                    SpaceViewStore.shared.select(.canvas, for: thinkspaceId)
                }
            }
        }
    }
    private func preserve() async {
        guard let thinkspaceId else { return }
        do { try await SpaceResearchService.preserveDocuments(in: thinkspaceId); preservationError = nil }
        catch { preservationError = "Your previous working notes couldn't be added to Materials. " + error.localizedDescription }
    }
}
struct SpaceCanvasWelcome: View {
    var purpose: String?
    var createNote: () -> Void
    var addMaterials: () -> Void
    var body: some View {
        VStack(spacing: DS.space16) {
            Image(systemName: "rectangle.3.group").font(DS.pageTitle).foregroundStyle(DS.textMuted)
            Text("Room to think").font(DS.title2).foregroundStyle(DS.text)
            Text(purpose.flatMap { $0.isEmpty ? nil : $0 } ?? "Place pages and sources side by side. Arrange them as your thinking takes shape.")
                .font(DS.body).foregroundStyle(DS.textSecondary).multilineTextAlignment(.center)
            HStack(spacing: DS.space20) {
                Button("New page", systemImage: "square.and.pencil", action: createNote)
                    .buttonStyle(.plain).foregroundStyle(DS.accent).help("Create a page on the canvas").frame(minHeight: 44)
                Button("Add materials", systemImage: "plus", action: addMaterials)
                    .buttonStyle(.plain).foregroundStyle(DS.textSecondary).help("Place existing material in this space").frame(minHeight: 44)
            }.font(DS.callout.weight(.medium))
        }.frame(maxWidth: 380).padding(DS.space32)
    }
}
