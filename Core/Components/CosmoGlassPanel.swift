// CosmoOS/Core/Components/CosmoGlassPanel.swift
// Shared spatial glass material for major sidebar/container panels.

import SwiftUI
import AppKit

enum CosmoGlassSceneSignalSource: String, Equatable {
    case canvasBlock
    case canvasCluster
    case commandTask
    case commandHabit
    case commandCalendar
    case inboxItem
    case inboxLane
    case inboxFilter
    case focusEntity
    case routeAccent
}

enum CosmoGlassMaterialMode: Equatable {
    case nativeOnly
    case canvasEdgeResponse
    case rimAccentOnly
}

struct CosmoGlassSceneSignal: Identifiable, Equatable {
    let id: String
    let color: Color
    let rect: CGRect
    let intensity: Double
    let source: CosmoGlassSceneSignalSource
    let allowsDeepDiffusion: Bool

    init(
        id: String,
        color: Color,
        rect: CGRect,
        intensity: Double = 1,
        source: CosmoGlassSceneSignalSource,
        allowsDeepDiffusion: Bool = false
    ) {
        self.id = id
        self.color = color
        self.rect = rect
        self.intensity = min(max(intensity, 0), 1)
        self.source = source
        self.allowsDeepDiffusion = allowsDeepDiffusion
    }

    static func == (lhs: CosmoGlassSceneSignal, rhs: CosmoGlassSceneSignal) -> Bool {
        lhs.id == rhs.id
            && lhs.rect == rhs.rect
            && lhs.intensity == rhs.intensity
            && lhs.source == rhs.source
            && lhs.allowsDeepDiffusion == rhs.allowsDeepDiffusion
    }

    func dampened(_ factor: Double) -> CosmoGlassSceneSignal {
        CosmoGlassSceneSignal(
            id: id,
            color: color,
            rect: rect,
            intensity: intensity * factor,
            source: source,
            allowsDeepDiffusion: allowsDeepDiffusion
        )
    }
}

struct CosmoGlassSceneMaterial {
    static let coordinateSpaceName = "cosmo-glass-scene"

    var fallbackTint: CosmoGlassSceneTint
    var signals: [CosmoGlassSceneSignal]
    var busyness: Double
    var luminanceBias: Double
    var mode: CosmoGlassMaterialMode

    init(
        fallbackTint: CosmoGlassSceneTint = .neutral,
        signals: [CosmoGlassSceneSignal] = [],
        busyness: Double = 0,
        luminanceBias: Double = 0,
        mode: CosmoGlassMaterialMode = .nativeOnly
    ) {
        self.fallbackTint = fallbackTint
        self.signals = Array(signals.prefix(8))
        self.busyness = min(max(busyness, 0), 1)
        self.luminanceBias = min(max(luminanceBias, -1), 1)
        self.mode = mode
    }

    static var fallback: CosmoGlassSceneMaterial {
        CosmoGlassSceneMaterial(fallbackTint: .fallback)
    }

    static var neutral: CosmoGlassSceneMaterial {
        CosmoGlassSceneMaterial(fallbackTint: .neutral)
    }

    static func fromTint(_ tint: CosmoGlassSceneTint) -> CosmoGlassSceneMaterial {
        CosmoGlassSceneMaterial(fallbackTint: tint, mode: .rimAccentOnly)
    }

    func dampened(_ factor: Double) -> CosmoGlassSceneMaterial {
        CosmoGlassSceneMaterial(
            fallbackTint: fallbackTint.dampened(factor),
            signals: signals.map { $0.dampened(factor) },
            busyness: busyness * factor,
            luminanceBias: luminanceBias,
            mode: mode
        )
    }

    func isVisuallyEquivalent(to other: CosmoGlassSceneMaterial) -> Bool {
        mode == other.mode
            && fallbackTint.visualKey == other.fallbackTint.visualKey
            && rounded(busyness) == rounded(other.busyness)
            && rounded(luminanceBias) == rounded(other.luminanceBias)
            && signals.map(\.visualKey) == other.signals.map(\.visualKey)
    }

    var representativeTint: CosmoGlassSceneTint {
        guard let strongest = signals.max(by: { $0.intensity < $1.intensity }) else {
            return fallbackTint
        }

        return CosmoGlassSceneTint(
            primary: strongest.color,
            secondary: fallbackTint.secondary,
            tertiary: fallbackTint.tertiary,
            intensity: max(fallbackTint.intensity, strongest.intensity),
            edgeIntensity: max(fallbackTint.edgeIntensity, strongest.intensity)
        )
    }

    private func rounded(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }
}

private extension CosmoGlassSceneSignal {
    var visualKey: String {
        [
            id,
            source.rawValue,
            "\(Int(rect.minX.rounded()))",
            "\(Int(rect.minY.rounded()))",
            "\(Int(rect.width.rounded()))",
            "\(Int(rect.height.rounded()))",
            "\(Int((intensity * 100).rounded()))",
            allowsDeepDiffusion ? "deep" : "edge"
        ].joined(separator: ":")
    }
}

struct CosmoGlassSceneSignalPreferenceKey: PreferenceKey {
    static let defaultValue: [CosmoGlassSceneSignal] = []

    static func reduce(value: inout [CosmoGlassSceneSignal], nextValue: () -> [CosmoGlassSceneSignal]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func cosmoGlassSceneSignal(
        id: String,
        source: CosmoGlassSceneSignalSource,
        color: Color,
        intensity: Double = 1,
        allowsDeepDiffusion: Bool = false
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CosmoGlassSceneSignalPreferenceKey.self,
                    value: [
                        CosmoGlassSceneSignal(
                            id: id,
                            color: color,
                            rect: proxy.frame(in: .named(CosmoGlassSceneMaterial.coordinateSpaceName)),
                            intensity: intensity,
                            source: source,
                            allowsDeepDiffusion: allowsDeepDiffusion
                        )
                    ]
                )
            }
        }
    }
}

struct CosmoGlassSceneTint {
    var primary: Color
    var secondary: Color
    var tertiary: Color
    var intensity: Double
    var edgeIntensity: Double

    init(
        primary: Color,
        secondary: Color? = nil,
        tertiary: Color? = nil,
        intensity: Double = 1,
        edgeIntensity: Double = 1
    ) {
        self.primary = primary
        self.secondary = secondary ?? primary
        self.tertiary = tertiary ?? secondary ?? primary
        self.intensity = min(max(intensity, 0), 1)
        self.edgeIntensity = min(max(edgeIntensity, 0), 1)
    }

    static var fallback: CosmoGlassSceneTint {
        CosmoGlassSceneTint(primary: DS.accent, secondary: DS.entityConnection, tertiary: DS.green)
    }

    static var neutral: CosmoGlassSceneTint {
        CosmoGlassSceneTint(
            primary: DS.textMuted,
            secondary: DS.surfaceElevated,
            tertiary: DS.borderActive,
            intensity: 0.10,
            edgeIntensity: 0.16
        )
    }

    func dampened(_ factor: Double) -> CosmoGlassSceneTint {
        CosmoGlassSceneTint(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            intensity: intensity * factor,
            edgeIntensity: edgeIntensity * factor
        )
    }

    var visualKey: String {
        "\(Int((intensity * 100).rounded())):\(Int((edgeIntensity * 100).rounded()))"
    }
}

extension Notification.Name {
    static let cosmoGlassSceneTintDidChange = Notification.Name("com.cosmo.glassSceneTintDidChange")
    static let cosmoGlassSceneMaterialDidChange = Notification.Name("com.cosmo.glassSceneMaterialDidChange")
}

enum CosmoGlassPanelRole {
    case globalSidebar
    case focusSidebar

    var material: NSVisualEffectView.Material {
        switch self {
        case .globalSidebar:
            return .sidebar
        case .focusSidebar:
            return .hudWindow
        }
    }

    var ambientMultiplier: Double {
        switch self {
        case .globalSidebar:
            return 1
        case .focusSidebar:
            return 0.58
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .globalSidebar:
            return 26
        case .focusSidebar:
            return 20
        }
    }

    var shadowYOffset: CGFloat {
        switch self {
        case .globalSidebar:
            return 10
        case .focusSidebar:
            return 8
        }
    }
}

struct CosmoGlassPanel<Content: View>: View {
    let sceneTint: CosmoGlassSceneTint
    let sceneMaterial: CosmoGlassSceneMaterial
    let role: CosmoGlassPanelRole
    let cornerRadius: CGFloat
    let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        sceneTint: CosmoGlassSceneTint = .fallback,
        sceneMaterial: CosmoGlassSceneMaterial? = nil,
        role: CosmoGlassPanelRole = .globalSidebar,
        cornerRadius: CGFloat = 22,
        @ViewBuilder content: () -> Content
    ) {
        self.sceneTint = sceneTint
        self.sceneMaterial = sceneMaterial ?? .fromTint(sceneTint)
        self.role = role
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                CosmoGlassPanelBackground(
                    sceneMaterial: sceneMaterial,
                    role: role,
                    cornerRadius: cornerRadius,
                    reduceTransparency: reduceTransparency
                )
            }
            .clipShape(shape)
            .overlay {
                CosmoGlassPanelRimOverlay(
                    sceneMaterial: sceneMaterial,
                    role: role,
                    cornerRadius: cornerRadius,
                    reduceTransparency: reduceTransparency
                )
            }
            .overlay {
                CosmoGlassPanelDepthOverlay(
                    sceneMaterial: sceneMaterial,
                    role: role,
                    cornerRadius: cornerRadius,
                    reduceTransparency: reduceTransparency
                )
            }
            .shadow(
                color: reduceTransparency ? Color.black.opacity(0.08) : DS.sidebarMaterialShadow,
                radius: role.shadowRadius,
                x: 0,
                y: role.shadowYOffset
            )
            .shadow(
                color: Color.black.opacity(DS.palette.isDark ? 0.065 : 0.026),
                radius: 4,
                x: 0,
                y: 1
            )
    }
}

private struct CosmoGlassPanelBackground: View {
    let sceneMaterial: CosmoGlassSceneMaterial
    let role: CosmoGlassPanelRole
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if reduceTransparency {
                shape.fill(DS.sidebarMaterialFallback)
            } else {
                nativeMaterialBackground(cornerRadius)
                shape.fill(DS.sidebarMaterialBase)
            }

            if !reduceTransparency {
                CosmoGlassEdgeResponseLayer(
                    sceneMaterial: sceneMaterial,
                    role: role
                )
            }

            if !reduceTransparency {
                CosmoGlassAmbientReflectionLayer(
                    sceneMaterial: sceneMaterial,
                    role: role
                )
            }

            if !reduceTransparency {
                FilmGrainOverlay(opacity: DS.sidebarMaterialNoiseOpacity)
                    .blendMode(DS.palette.isDark ? .screen : .multiply)
            }
        }
        .clipShape(shape)
    }

    @ViewBuilder
    private func nativeMaterialBackground(_ cornerRadius: CGFloat) -> some View {
        VisualEffectBlur(
            material: role.material,
            blendingMode: .withinWindow,
            state: .active,
            isEmphasized: false,
            cornerRadius: cornerRadius
        )
        .allowsHitTesting(false)
    }
}

private struct CosmoGlassEdgeResponseLayer: View {
    let sceneMaterial: CosmoGlassSceneMaterial
    let role: CosmoGlassPanelRole

    var body: some View {
        GeometryReader { geo in
            let panelFrame = geo.frame(in: .named(CosmoGlassSceneMaterial.coordinateSpaceName))
            let response = edgeResponse(for: panelFrame)

            LinearGradient(
                colors: [
                    Color.clear,
                    response.color.opacity(response.opacity * 0.18),
                    response.color.opacity(response.opacity)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: response.width)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(response.opacity > 0 ? 1 : 0)
        }
        .blendMode(DS.palette.isDark ? .screen : .plusLighter)
        .allowsHitTesting(false)
    }

    private struct EdgeResponse {
        let color: Color
        let opacity: Double
        let width: CGFloat
    }

    private func edgeResponse(for panelFrame: CGRect) -> EdgeResponse {
        guard sceneMaterial.mode != .nativeOnly else {
            return EdgeResponse(color: .clear, opacity: 0, width: 1)
        }

        let tint = sceneMaterial.representativeTint

        guard sceneMaterial.mode == .canvasEdgeResponse else {
            let cap = DS.sidebarMaterialRimAccentOpacity
            return EdgeResponse(
                color: tint.primary,
                opacity: min(cap * 0.45 * tint.edgeIntensity * role.ambientMultiplier, cap * 0.45),
                width: 28
            )
        }

        let panelRight = panelFrame.maxX
        let strongest = sceneMaterial.signals
            .compactMap { signal -> (CosmoGlassSceneSignal, Double)? in
                guard signal.rect.width > 1, signal.rect.height > 1 else { return nil }

                let overlapsPanel = signal.rect.intersects(panelFrame.insetBy(dx: -24, dy: -28))
                let distance = max(0, signal.rect.minX - panelRight)
                let normalizedDistance = min(distance / 820, 1)
                let response = overlapsPanel ? 1 : pow(1 - normalizedDistance, 1.65)
                guard response > 0.02 else { return nil }

                return (signal, response * signal.intensity)
            }
            .max { $0.1 < $1.1 }

        guard let strongest else {
            return EdgeResponse(color: tint.primary, opacity: 0, width: 1)
        }

        let cap = DS.sidebarMaterialCanvasEdgeOpacity
        return EdgeResponse(
            color: strongest.0.color,
            opacity: min(cap * strongest.1 * role.ambientMultiplier, cap),
            width: strongest.0.allowsDeepDiffusion ? 118 : 74
        )
    }
}

private struct CosmoGlassAmbientReflectionLayer: View {
    let sceneMaterial: CosmoGlassSceneMaterial
    let role: CosmoGlassPanelRole

    var body: some View {
        GeometryReader { geo in
            let panelFrame = geo.frame(in: .named(CosmoGlassSceneMaterial.coordinateSpaceName))
            let reflections = ambientReflections(for: panelFrame)

            ZStack {
                ForEach(reflections) { reflection in
                    RadialGradient(
                        colors: [
                            reflection.color.opacity(reflection.opacity),
                            reflection.color.opacity(reflection.opacity * 0.45),
                            Color.clear
                        ],
                        center: UnitPoint(x: 1.08, y: reflection.unitY),
                        startRadius: 0,
                        endRadius: max(geo.size.width, geo.size.height) * 0.96
                    )
                }
            }
        }
        .blendMode(DS.palette.isDark ? .screen : .plusLighter)
        .allowsHitTesting(false)
    }

    private struct AmbientReflection: Identifiable {
        let id: String
        let color: Color
        let opacity: Double
        let unitY: Double
        let strength: Double
    }

    private func ambientReflections(for panelFrame: CGRect) -> [AmbientReflection] {
        guard sceneMaterial.mode == .canvasEdgeResponse else {
            let tint = sceneMaterial.representativeTint
            let opacity = DS.sidebarMaterialAmbientOpacity * 0.42 * tint.intensity * role.ambientMultiplier
            guard opacity > 0 else { return [] }
            return [
                AmbientReflection(
                    id: "fallback",
                    color: tint.primary,
                    opacity: opacity,
                    unitY: 0.50,
                    strength: opacity
                )
            ]
        }

        let panelRight = panelFrame.maxX
        let cap = DS.sidebarMaterialAmbientOpacity
        return sceneMaterial.signals
            .compactMap { signal -> AmbientReflection? in
                guard signal.rect.width > 1, signal.rect.height > 1 else { return nil }

                let overlapsPanel = signal.rect.intersects(panelFrame.insetBy(dx: -32, dy: -44))
                let distance = max(0, signal.rect.minX - panelRight)
                let normalizedDistance = min(distance / 1_100, 1)
                let distanceResponse = overlapsPanel ? 1 : pow(1 - normalizedDistance, 1.38)
                guard distanceResponse > 0.035 else { return nil }

                let unitY = clampedUnitY(
                    panelFrame.height > 1
                        ? (signal.rect.midY - panelFrame.minY) / panelFrame.height
                        : 0.5
                )
                let diffusionBoost = signal.allowsDeepDiffusion ? 1.28 : 0.90
                let opacity = min(
                    cap * signal.intensity * distanceResponse * diffusionBoost * role.ambientMultiplier,
                    cap
                )

                return AmbientReflection(
                    id: signal.id,
                    color: signal.color,
                    opacity: opacity,
                    unitY: unitY,
                    strength: opacity
                )
            }
            .sorted { $0.strength > $1.strength }
            .prefix(4)
            .map { $0 }
    }

    private func clampedUnitY(_ value: CGFloat) -> Double {
        min(max(Double(value), 0.08), 0.92)
    }
}

private struct CosmoGlassPanelDepthOverlay: View {
    let sceneMaterial: CosmoGlassSceneMaterial
    let role: CosmoGlassPanelRole
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        LinearGradient(
            colors: [
                Color.clear,
                DS.sidebarMaterialInnerShade
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

private struct CosmoGlassPanelRimOverlay: View {
    let sceneMaterial: CosmoGlassSceneMaterial
    let role: CosmoGlassPanelRole
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.strokeBorder(outerSeparationGradient, lineWidth: 0.9)
            shape
                .inset(by: 0.75)
                .strokeBorder(innerSpecularGradient, lineWidth: 0.55)
        }
        .allowsHitTesting(false)
    }

    private var outerSeparationGradient: LinearGradient {
        LinearGradient(
            colors: [
                DS.sidebarMaterialBorder.opacity(reduceTransparency ? 0.70 : 0.42),
                DS.sidebarMaterialBorder.opacity(0.56),
                rimTint.opacity(edgeOpacity),
                Color.black.opacity(DS.palette.isDark ? 0.20 : 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var innerSpecularGradient: LinearGradient {
        LinearGradient(
            colors: [
                DS.sidebarMaterialHighlight.opacity(reduceTransparency ? 0.42 : 0.16),
                DS.sidebarMaterialHighlight.opacity(reduceTransparency ? 0.18 : 0.055),
                rimTint.opacity(edgeOpacity * 0.62),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var rimTint: Color {
        sceneMaterial.representativeTint.primary
    }

    private var edgeOpacity: Double {
        guard !reduceTransparency else { return 0 }
        let cap: Double
        switch sceneMaterial.mode {
        case .nativeOnly:
            cap = 0
        case .canvasEdgeResponse:
            cap = DS.sidebarMaterialCanvasEdgeOpacity
        case .rimAccentOnly:
            cap = DS.sidebarMaterialRimAccentOpacity
        }
        return min(cap * sceneMaterial.representativeTint.edgeIntensity * role.ambientMultiplier, cap)
    }
}

extension View {
    func cosmoGlassPanel(
        sceneTint: CosmoGlassSceneTint = .fallback,
        sceneMaterial: CosmoGlassSceneMaterial? = nil,
        role: CosmoGlassPanelRole = .globalSidebar,
        cornerRadius: CGFloat = 22
    ) -> some View {
        CosmoGlassPanel(sceneTint: sceneTint, sceneMaterial: sceneMaterial, role: role, cornerRadius: cornerRadius) {
            self
        }
    }
}
