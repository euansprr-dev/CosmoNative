// CosmoOS/Core/Components/CosmoGlassPanel.swift
// Shared Liquid Glass material for major sidebar/container panels (macOS 26+).

import SwiftUI

// MARK: - Panel Roles

enum CosmoGlassPanelRole {
    case globalSidebar
    case focusSidebar
    case floatingAssistant

    /// Native Liquid Glass variant for the role. The tint keeps the Greenhouse
    /// parchment warmth in light themes and a neutral smoke in dark themes.
    var glass: Glass {
        switch self {
        case .globalSidebar:
            return .regular.tint(DS.glassPanelTint)
        case .focusSidebar:
            return .regular.tint(DS.glassPanelTint.opacity(0.6))
        case .floatingAssistant:
            return .regular.tint(DS.glassPanelTint)
        }
    }

    var shadowRadius: CGFloat {
        self == .focusSidebar ? 12 : 18
    }

    var shadowYOffset: CGFloat {
        self == .focusSidebar ? 4 : 6
    }
}

// MARK: - Panel

struct CosmoGlassPanel<Content: View>: View {
    let role: CosmoGlassPanelRole
    let cornerRadius: CGFloat
    let glassID: String?
    let glassNamespace: Namespace.ID?
    let content: Content

    init(
        role: CosmoGlassPanelRole = .globalSidebar,
        cornerRadius: CGFloat = 22,
        glassID: String? = nil,
        glassNamespace: Namespace.ID? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.cornerRadius = cornerRadius
        self.glassID = glassID
        self.glassNamespace = glassNamespace
        self.content = content()
    }

    var body: some View {
        glassBase
            .background(shadowCaster)
    }

    /// The drop shadow is cast by this dedicated shape, never by the glass
    /// composite: the AppKit-backed glass layer can reach its first frame with
    /// square corners, which froze a hard-cornered shadow into place until the
    /// next invalidation. A plain shape is rounded from frame one. The interior
    /// is erased so the shadow is a pure outer ring and the backdrop behind the
    /// translucent glass stays undarkened.
    private var shadowCaster: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(.black)
            .shadow(
                color: DS.glassPanelShadow,
                radius: role.shadowRadius,
                x: 0,
                y: role.shadowYOffset
            )
            .overlay(shape.fill(.black).blendMode(.destinationOut))
            .compositingGroup()
    }

    @ViewBuilder
    private var glassBase: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let base = content
            .clipShape(shape)
            .glassEffect(role.glass, in: shape)
            .glassEffectTransition(.materialize)

        if let glassID, let glassNamespace {
            base.glassEffectID(glassID, in: glassNamespace)
        } else {
            base
        }
    }
}

extension View {
    func cosmoGlassPanel(
        role: CosmoGlassPanelRole = .globalSidebar,
        cornerRadius: CGFloat = 22,
        glassID: String? = nil,
        glassNamespace: Namespace.ID? = nil
    ) -> some View {
        CosmoGlassPanel(
            role: role,
            cornerRadius: cornerRadius,
            glassID: glassID,
            glassNamespace: glassNamespace
        ) {
            self
        }
    }
}
