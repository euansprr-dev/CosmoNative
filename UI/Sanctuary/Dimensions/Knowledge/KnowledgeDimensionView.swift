// CosmoOS/UI/Sanctuary/Dimensions/Knowledge/KnowledgeDimensionView.swift
// Lightweight wrapper over the shared dimension workspace shell

import SwiftUI

public struct KnowledgeDimensionView: View {
    let onBack: () -> Void

    public init(
        data: KnowledgeDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        self.onBack = onBack
    }

    public var body: some View {
        DimensionWorkspaceView(
            dimension: .knowledge,
            preferredPresentation: .primary,
            onBack: onBack
        )
    }
}

#if DEBUG
struct KnowledgeDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        KnowledgeDimensionView(onBack: {})
            .frame(width: 1280, height: 820)
    }
}
#endif
