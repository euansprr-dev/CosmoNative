// CosmoOS/Core/Theming/ThemeManager.swift
// Central theme manager — persists selection, swaps DS palette, triggers re-render.

import SwiftUI

/// All available themes in CosmoOS.
enum CosmoAppTheme: String, CaseIterable, Identifiable {
    case greenhouse
    case codexMono
    case blackMono
    case midnightStudy
    case nordicFrost
    case terracotta
    case obsidian

    var id: String { rawValue }

    var palette: ThemePalette {
        switch self {
        case .greenhouse: GreenhousePalette()
        case .codexMono: CodexMonoPalette()
        case .blackMono: BlackMonoPalette()
        case .midnightStudy: MidnightStudyPalette()
        case .nordicFrost: NordicFrostPalette()
        case .terracotta: TerracottaPalette()
        case .obsidian: ObsidianPalette()
        }
    }

    var displayName: String {
        switch self {
        case .greenhouse: "Greenhouse"
        case .codexMono: "Codex Mono"
        case .blackMono: "Black Mono"
        case .midnightStudy: "Midnight Study"
        case .nordicFrost: "Nordic Frost"
        case .terracotta: "Terracotta"
        case .obsidian: "Obsidian"
        }
    }

    var icon: String { palette.icon }
    var isDark: Bool { palette.isDark }

    var tagline: String {
        switch self {
        case .greenhouse: "Morning coffee in a sunlit studio"
        case .codexMono: "Black and white workspace with colored signal cues"
        case .blackMono: "Black mono workspace with white signal"
        case .midnightStudy: "Late-night deep work by lamplight"
        case .nordicFrost: "Scandinavian clarity on a winter morning"
        case .terracotta: "Mediterranean creative studio at golden hour"
        case .obsidian: "Deep focus cave with electric clarity"
        }
    }
}

/// Manages the active theme. Swaps the DS palette and posts a notification for full re-render.
@Observable @MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    var currentTheme: CosmoAppTheme {
        didSet {
            DS.palette = currentTheme.palette
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "cosmoTheme")
            NotificationCenter.default.post(name: CosmoNotification.Theme.changed, object: nil)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "cosmoTheme") ?? "greenhouse"
        self.currentTheme = CosmoAppTheme(rawValue: saved) ?? .greenhouse
        DS.palette = currentTheme.palette
    }

    func setTheme(_ theme: CosmoAppTheme) {
        guard theme != currentTheme else { return }
        currentTheme = theme
    }
}
