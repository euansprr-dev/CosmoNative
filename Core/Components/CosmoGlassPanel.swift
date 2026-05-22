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

private struct CosmoGlassSceneSignalsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var cosmoGlassSceneSignalsEnabled: Bool {
        get { self[CosmoGlassSceneSignalsEnabledKey.self] }
        set { self[CosmoGlassSceneSignalsEnabledKey.self] = newValue }
    }
}

extension View {
    func cosmoGlassSceneSignal(
        id: String,
        source: CosmoGlassSceneSignalSource,
        color: Color,
        intensity: Double = 1,
        allowsDeepDiffusion: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        modifier(CosmoGlassSceneSignalModifier(
            id: id,
            source: source,
            color: color,
            intensity: intensity,
            allowsDeepDiffusion: allowsDeepDiffusion,
            isEnabled: isEnabled
        ))
    }

    func cosmoGlassSceneSignalsEnabled(_ isEnabled: Bool) -> some View {
        environment(\.cosmoGlassSceneSignalsEnabled, isEnabled)
    }
}

private struct CosmoGlassSceneSignalModifier: ViewModifier {
    let id: String
    let source: CosmoGlassSceneSignalSource
    let color: Color
    let intensity: Double
    let allowsDeepDiffusion: Bool
    let isEnabled: Bool

    @Environment(\.cosmoGlassSceneSignalsEnabled) private var environmentEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled && environmentEnabled {
            content.background {
                sceneSignalPreference
            }
        } else {
            content
        }
    }

    private var sceneSignalPreference: some View {
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
    case floatingAssistant

    private var usesMonoMaterial: Bool {
        DS.palette.name == "Codex Mono" || DS.palette.name == "Black Mono"
    }

    var material: NSVisualEffectView.Material {
        switch self {
        case .globalSidebar:
            return usesMonoMaterial ? .popover : .sidebar
        case .focusSidebar:
            return .hudWindow
        case .floatingAssistant:
            return .hudWindow
        }
    }

    var ambientMultiplier: Double {
        switch self {
        case .globalSidebar:
            return 1
        case .focusSidebar:
            return 0.58
        case .floatingAssistant:
            return 0.72
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .globalSidebar:
            return usesMonoMaterial ? 40 : 34
        case .focusSidebar:
            return 20
        case .floatingAssistant:
            return 30
        }
    }

    var shadowYOffset: CGFloat {
        switch self {
        case .globalSidebar:
            return usesMonoMaterial ? 11 : 10
        case .focusSidebar:
            return 8
        case .floatingAssistant:
            return 12
        }
    }

    var sideShadowRadius: CGFloat {
        switch self {
        case .globalSidebar:
            return 46
        case .focusSidebar:
            return 26
        case .floatingAssistant:
            return 34
        }
    }

    var sideShadowXOffset: CGFloat {
        switch self {
        case .globalSidebar:
            return 18
        case .focusSidebar:
            return 10
        case .floatingAssistant:
            return 0
        }
    }

    var sideShadowOpacity: Double {
        switch self {
        case .globalSidebar:
            if usesMonoMaterial { return 0.074 }
            return DS.palette.isDark ? 0.12 : 0.058
        case .focusSidebar:
            return DS.palette.isDark ? 0.08 : 0.032
        case .floatingAssistant:
            return DS.palette.isDark ? 0.10 : 0.048
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
                    role: role,
                    cornerRadius: cornerRadius,
                    reduceTransparency: reduceTransparency
                )
            }
            .clipShape(shape)
            .overlay {
                if !reduceTransparency {
                    CosmoGlassPanelSceneDiffusionOverlay(
                        sceneMaterial: sceneMaterial,
                        role: role,
                        cornerRadius: cornerRadius
                    )
                }
            }
            .overlay {
                CosmoGlassPanelDepthOverlay(
                    cornerRadius: cornerRadius,
                    reduceTransparency: reduceTransparency
                )
            }
            .overlay {
                CosmoGlassPanelRimOverlay(
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
                color: Color.black.opacity(reduceTransparency ? 0.05 : role.sideShadowOpacity),
                radius: role.sideShadowRadius,
                x: role.sideShadowXOffset,
                y: 0
            )
            .shadow(
                color: Color.black.opacity(DS.palette.isDark ? 0.078 : 0.034),
                radius: 6,
                x: 1.5,
                y: 1
            )
    }
}

private struct CosmoGlassPanelSceneDiffusionOverlay: View {
    let sceneMaterial: CosmoGlassSceneMaterial
    let role: CosmoGlassPanelRole
    let cornerRadius: CGFloat
    private let reflectionStrengthScale = 0.5

    var body: some View {
        GeometryReader { proxy in
            let panelFrame = proxy.frame(in: .named(CosmoGlassSceneMaterial.coordinateSpaceName))
            let resolvedSignals = resolvedSignals(panelFrame: panelFrame, panelSize: proxy.size)

            ZStack {
                CosmoGlassFallbackDiffusion(
                    tint: sceneMaterial.fallbackTint,
                    mode: sceneMaterial.mode,
                    panelSize: proxy.size,
                    role: role
                )

                ForEach(resolvedSignals) { signal in
                    CosmoGlassSignalDiffusion(signal: signal, panelSize: proxy.size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .blendMode(DS.palette.isDark ? .screen : .softLight)
            .drawingGroup(opaque: false, colorMode: .linear)
            .allowsHitTesting(false)
        }
    }

    private func resolvedSignals(panelFrame: CGRect, panelSize: CGSize) -> [ResolvedGlassDiffusionSignal] {
        sceneMaterial.signals.compactMap { signal in
            let distanceFromPanel = max(0, signal.rect.minX - panelFrame.maxX)
            let maxDistance = maxDiffusionDistance(for: signal)
            guard distanceFromPanel <= maxDistance else { return nil }

            let relativeY = signal.rect.midY - panelFrame.minY
            let verticalReach = max(signal.rect.height * (signal.allowsDeepDiffusion ? 1.85 : 1.35), 120)
            guard relativeY + verticalReach * 0.55 >= -120,
                  relativeY - verticalReach * 0.55 <= panelSize.height + 120 else { return nil }

            let proximity = pow(
                max(0, 1 - Double(distanceFromPanel / maxDistance)),
                signal.allowsDeepDiffusion ? 1.12 : 1.72
            )
            let sourceBoost = boost(for: signal.source)
            let nearEdgeBoost = distanceFromPanel < 180 ? 1.18 : 1
            let largeSurfaceScale = broadCommandSurfaceScale(for: signal, panelSize: panelSize)
            let rawStrength = signal.intensity
                * proximity
                * sourceBoost
                * nearEdgeBoost
                * largeSurfaceScale
                * role.ambientMultiplier
                * reflectionStrengthScale
            let strength = min(max(rawStrength, 0), signal.allowsDeepDiffusion ? 0.72 : 0.54)

            guard strength > 0.018 else { return nil }

            return ResolvedGlassDiffusionSignal(
                id: signal.id,
                color: signal.color,
                source: signal.source,
                relativeY: relativeY,
                height: min(max(verticalReach, 108), signal.allowsDeepDiffusion ? 680 : 380),
                strength: strength,
                allowsDeepDiffusion: signal.allowsDeepDiffusion
            )
        }
    }

    private func maxDiffusionDistance(for signal: CosmoGlassSceneSignal) -> CGFloat {
        let standardDistance: CGFloat = signal.allowsDeepDiffusion ? 1_180 : 680

        switch signal.source {
        case .canvasBlock, .canvasCluster:
            return standardDistance * 0.5
        case .commandTask, .commandCalendar, .commandHabit:
            return standardDistance * 0.45
        case .routeAccent:
            return standardDistance * 0.40
        default:
            return standardDistance
        }
    }

    private func broadCommandSurfaceScale(for signal: CosmoGlassSceneSignal, panelSize: CGSize) -> Double {
        switch signal.source {
        case .commandTask, .commandCalendar, .commandHabit:
            let isBroadSurface = signal.rect.width > panelSize.width * 1.6
                || signal.rect.height > panelSize.height * 0.42
            return isBroadSurface ? 0.34 : 1
        case .routeAccent:
            return 0.42
        default:
            return 1
        }
    }

    private func boost(for source: CosmoGlassSceneSignalSource) -> Double {
        switch source {
        case .canvasBlock:
            return 1.12
        case .canvasCluster:
            return 1.04
        case .commandTask:
            return 0.66
        case .commandCalendar:
            return 0.58
        case .commandHabit:
            return 0.50
        case .inboxItem, .inboxLane:
            return 0.90
        case .inboxFilter, .routeAccent:
            return 0.46
        case .focusEntity:
            return 0.76
        }
    }
}

private struct ResolvedGlassDiffusionSignal: Identifiable {
    let id: String
    let color: Color
    let source: CosmoGlassSceneSignalSource
    let relativeY: CGFloat
    let height: CGFloat
    let strength: Double
    let allowsDeepDiffusion: Bool
}

private struct CosmoGlassFallbackDiffusion: View {
    let tint: CosmoGlassSceneTint
    let mode: CosmoGlassMaterialMode
    let panelSize: CGSize
    let role: CosmoGlassPanelRole

    var body: some View {
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.primary.opacity(edgeOpacity * 0.82),
                            tint.secondary.opacity(edgeOpacity * 0.34),
                            Color.clear
                        ],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
                .frame(width: min(panelSize.width * 0.72, 230))
                .frame(maxWidth: .infinity, alignment: .trailing)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.tertiary.opacity(bodyOpacity),
                            tint.primary.opacity(bodyOpacity * 0.42),
                            Color.clear
                        ],
                        center: .trailing,
                        startRadius: 0,
                        endRadius: max(panelSize.width, panelSize.height) * 0.82
                    )
                )
                .frame(width: panelSize.width * 1.15, height: panelSize.height * 0.86)
                .position(x: panelSize.width * 1.02, y: panelSize.height * 0.48)
                .blur(radius: 34)
        }
        .opacity(mode == .nativeOnly ? 0.42 : 1)
    }

    private var edgeOpacity: Double {
        tint.edgeIntensity * 0.13 * role.ambientMultiplier
    }

    private var bodyOpacity: Double {
        tint.intensity * 0.085 * role.ambientMultiplier
    }
}

private struct CosmoGlassSignalDiffusion: View {
    let signal: ResolvedGlassDiffusionSignal
    let panelSize: CGSize

    var body: some View {
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            signal.color.opacity(signal.strength * 0.22),
                            signal.color.opacity(signal.strength * 0.10),
                            Color.clear
                        ],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
                .frame(width: edgeWidth, height: max(signal.height * edgeHeightScale, 86))
                .position(x: panelSize.width - edgeWidth / 2, y: balancedY)
                .blur(radius: signal.allowsDeepDiffusion ? 18 : 12)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            signal.color.opacity(signal.strength * 0.28),
                            signal.color.opacity(signal.strength * 0.12),
                            Color.clear
                        ],
                        center: .trailing,
                        startRadius: 0,
                        endRadius: max(signal.height, panelSize.width) * 0.78
                    )
                )
                .frame(width: panelSize.width * 1.16, height: signal.height * bodyHeightScale)
                .position(x: panelSize.width * 0.98, y: balancedY)
                .blur(radius: signal.allowsDeepDiffusion ? 40 : 26)

            if needsVerticalEqualization {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                signal.color.opacity(signal.strength * 0.075),
                                signal.color.opacity(signal.strength * 0.035),
                                Color.clear
                            ],
                            center: UnitPoint(x: 1, y: 0.58),
                            startRadius: 0,
                            endRadius: max(signal.height, panelSize.width) * 0.74
                        )
                    )
                    .frame(width: panelSize.width * 1.08, height: signal.height * 0.72)
                    .position(x: panelSize.width * 0.99, y: balancedY + lowerBalanceOffset)
                    .blur(radius: signal.allowsDeepDiffusion ? 34 : 22)
            }

            Rectangle()
                .fill(signal.color.opacity(signal.strength * 0.34))
                .frame(width: 8, height: max(signal.height * rimHeightScale, 72))
                .position(x: panelSize.width - 4, y: balancedY)
                .blur(radius: 14)
        }
    }

    private var edgeWidth: CGFloat {
        min(panelSize.width * (signal.allowsDeepDiffusion ? 0.86 : 0.64), signal.allowsDeepDiffusion ? 260 : 190)
    }

    private var balancedY: CGFloat {
        signal.relativeY + centerCorrection
    }

    private var centerCorrection: CGFloat {
        switch signal.source {
        case .canvasCluster:
            return min(max(signal.height * 0.075, 18), 54)
        case .commandTask, .commandCalendar, .commandHabit:
            return min(max(signal.height * 0.060, 10), 32)
        default:
            return 0
        }
    }

    private var needsVerticalEqualization: Bool {
        switch signal.source {
        case .canvasCluster, .commandTask, .commandCalendar, .commandHabit:
            return true
        default:
            return false
        }
    }

    private var lowerBalanceOffset: CGFloat {
        switch signal.source {
        case .canvasCluster:
            return min(max(signal.height * 0.13, 22), 76)
        case .commandTask, .commandCalendar, .commandHabit:
            return min(max(signal.height * 0.11, 14), 42)
        default:
            return 0
        }
    }

    private var edgeHeightScale: CGFloat {
        needsVerticalEqualization ? 0.88 : 0.78
    }

    private var bodyHeightScale: CGFloat {
        needsVerticalEqualization ? 1.08 : 1
    }

    private var rimHeightScale: CGFloat {
        needsVerticalEqualization ? 0.66 : 0.58
    }
}

private struct CosmoGlassPanelBackground: View {
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
        .opacity(DS.sidebarMaterialNativeOpacity)
        .allowsHitTesting(false)
    }
}

private struct CosmoGlassPanelDepthOverlay: View {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        if !reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            DS.sidebarMaterialInnerShade
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
    }
}

private struct CosmoGlassPanelRimOverlay: View {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.strokeBorder(outerSeparationColor, lineWidth: 0.9)
            shape
                .inset(by: 0.75)
                .strokeBorder(innerHighlightColor, lineWidth: 0.55)
        }
        .allowsHitTesting(false)
    }

    private var outerSeparationColor: Color {
        DS.sidebarMaterialBorder.opacity(reduceTransparency ? 0.70 : 0.52)
    }

    private var innerHighlightColor: Color {
        DS.sidebarMaterialHighlight.opacity(reduceTransparency ? 0.24 : 0.10)
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
