// CosmoOS/UI/Sanctuary/Dimensions/Reflection/ReflectionDimensionView.swift
// Lightweight wrapper over the shared dimension workspace shell

import SwiftUI

public struct ReflectionDimensionView: View {
    let onBack: () -> Void

    public init(
        data: ReflectionDimensionData = .empty,
        onBack: @escaping () -> Void
    ) {
        self.onBack = onBack
    }

    public var body: some View {
        DimensionWorkspaceView(
            dimension: .reflection,
            preferredPresentation: .primary,
            onBack: onBack
        )
    }
}

#if DEBUG
struct ReflectionDimensionView_Previews: PreviewProvider {
    static var previews: some View {
        ReflectionDimensionView(onBack: {})
            .frame(width: 1280, height: 820)
    }
}
#endif
