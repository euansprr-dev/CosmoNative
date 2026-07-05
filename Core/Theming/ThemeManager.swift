// CosmoOS/Core/Theming/ThemeManager.swift
// Theme = family × appearance, in lockstep with the iOS ThemeStore. Two
// identities (Mono, Greenhouse), each with a day and a night face; the
// appearance switch (system/light/dark) picks the face. Persists selection,
// swaps the DS palette, and posts Theme.changed for a full re-render.

import SwiftUI

/// A theme identity with a day and a night face.
enum ThemeFamily: String, CaseIterable, Identifiable {
    case mono
    case greenhouse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mono: return "Mono"
        case .greenhouse: return "Greenhouse"
        }
    }

    var tagline: String {
        switch self {
        case .mono: return "Ink on paper — pure black and white"
        case .greenhouse: return "Parchment and forest green, lamplit at night"
        }
    }

    var lightPalette: ThemePalette {
        switch self {
        case .mono: return CodexMonoPalette()
        case .greenhouse: return GreenhousePalette()
        }
    }

    var darkPalette: ThemePalette {
        switch self {
        case .mono: return BlackMonoPalette()
        case .greenhouse: return GreenhouseNightPalette()
        }
    }
}

/// System follows macOS; light/dark pin one face.
enum ThemeAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Manages the active theme. Swaps the DS palette and posts a notification
/// for full re-render. Legacy single-theme selections ("cosmoTheme") migrate
/// to the nearest family × appearance on first launch.
@Observable @MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    private static let familyKey = "theme.family"
    private static let appearanceKey = "theme.appearance"
    private static let legacyKey = "cosmoTheme"

    var family: ThemeFamily {
        didSet {
            UserDefaults.standard.set(family.rawValue, forKey: Self.familyKey)
            refresh()
        }
    }

    var appearance: ThemeAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            refresh()
        }
    }

    /// The resolved face — what every surface actually wears.
    private(set) var palette: ThemePalette

    var isDark: Bool { palette.isDark }

    private init() {
        let defaults = UserDefaults.standard
        var family = defaults.string(forKey: Self.familyKey).flatMap(ThemeFamily.init(rawValue:))
        var appearance = defaults.string(forKey: Self.appearanceKey).flatMap(ThemeAppearance.init(rawValue:))

        // Migrate the legacy single-theme selection to family × appearance.
        if family == nil, appearance == nil, let legacy = defaults.string(forKey: Self.legacyKey) {
            switch legacy {
            case "codexMono": (family, appearance) = (.mono, .light)
            case "blackMono": (family, appearance) = (.mono, .dark)
            case "greenhouse": (family, appearance) = (.greenhouse, .light)
            case "midnightStudy", "obsidian": (family, appearance) = (.greenhouse, .dark)
            default: (family, appearance) = (.greenhouse, .light) // nordicFrost, terracotta
            }
        }

        let resolvedFamily = family ?? .greenhouse
        let resolvedAppearance = appearance ?? .system
        self.family = resolvedFamily
        self.appearance = resolvedAppearance
        self.palette = Self.resolve(family: resolvedFamily, appearance: resolvedAppearance)
        defaults.set(resolvedFamily.rawValue, forKey: Self.familyKey)
        defaults.set(resolvedAppearance.rawValue, forKey: Self.appearanceKey)
        DS.palette = palette

        // System mode follows the macOS appearance live.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard ThemeManager.shared.appearance == .system else { return }
                ThemeManager.shared.refresh()
            }
        }
    }

    func setFamily(_ family: ThemeFamily) {
        guard family != self.family else { return }
        self.family = family
    }

    func setAppearance(_ appearance: ThemeAppearance) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
    }

    private static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    private static func resolve(family: ThemeFamily, appearance: ThemeAppearance) -> ThemePalette {
        let dark = appearance == .dark || (appearance == .system && systemIsDark)
        return dark ? family.darkPalette : family.lightPalette
    }

    private func refresh() {
        let next = Self.resolve(family: family, appearance: appearance)
        guard next.name != palette.name else { return }
        palette = next
        DS.palette = next
        NotificationCenter.default.post(name: CosmoNotification.Theme.changed, object: nil)
    }
}
