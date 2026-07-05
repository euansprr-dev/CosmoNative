// CosmoOS/UI/FocusMode/Inquiry/InquiryWorkspaceView.swift
// Thin host for the Study shell. The workspace itself — one manuscript page
// with four pieces of floating glass — lives in Study/StudyShellView.swift.
// This file owns only the view model's lifecycle and legacy notifications.

import SwiftUI

@MainActor
struct InquiryWorkspaceView: View {
    let sessionAtom: Atom
    let onClose: () -> Void

    @State private var viewModel: InquiryWorkspaceViewModel

    init(sessionAtom: Atom, onClose: @escaping () -> Void) {
        self.sessionAtom = sessionAtom
        self.onClose = onClose
        self._viewModel = State(initialValue: InquiryWorkspaceViewModel(session: sessionAtom))
    }

    var body: some View {
        StudyShellView(viewModel: viewModel, onClose: onClose)
            .onReceive(NotificationCenter.default.publisher(for: CosmoNotification.Inquiry.layoutRequested)) { notification in
                guard let payload = CosmoNotification.Inquiry.LayoutPayload(from: notification) else { return }
                viewModel.setLayout(payload.mode)
            }
    }
}
