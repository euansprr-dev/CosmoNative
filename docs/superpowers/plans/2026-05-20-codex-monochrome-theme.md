# Codex Monochrome Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new Codex-inspired black-and-white light theme that feels cleaner and more premium than Greenhouse while preserving meaningful semantic colors for icons, statuses, sidebars, and command-center cues.

**Architecture:** Implement one new `ThemePalette` and register it through `CosmoAppTheme`, leaving all existing themes and defaults intact. The app already routes most chrome through `DS`, so the work should stay inside the theme layer plus one targeted test file and Xcode project membership.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, existing `DS` theme tokens, `CosmoOS.xcodeproj`.

---

## Design Direction

Recommended approach: add a palette-only theme named `Codex Mono`.

This matches the Codex screenshots by making the app chrome monochrome: white content surfaces, a soft neutral gray sidebar/panel layer, charcoal primary actions, and quiet borders. This is not a grayscale-only theme. Blue, orange, red, yellow, green, and other semantic/icon colors should still appear where color carries meaning, such as command-center categories, sidebar icons, timers, warnings, errors, info states, habit markers, and existing entity identity colors. Greenhouse remains available, so this is a reversible experiment rather than a destructive redesign.

Rejected alternatives:

- Replacing Greenhouse: too risky because it removes the current default and makes comparison harder.
- Global UI redesign: unnecessary for a first test because most visible surfaces already consume `DS` tokens.
- New dark theme: Obsidian already covers the dark-premium direction; this request is specifically the light Codex/macOS look.

## File Structure

- Create `Core/Theming/CodexMonoPalette.swift`: the new monochrome light palette.
- Modify `Core/Theming/ThemeManager.swift`: add `.codexMono`, display name, tagline, and palette routing.
- Modify `CosmoOS.xcodeproj/project.pbxproj`: include `CodexMonoPalette.swift` in the Theming group and `CosmoOS` target sources.
- Create `Tests/CosmoOSTests/ThemePaletteTests.swift`: lock down the new palette's neutral surfaces, charcoal accent, semantic color distinction, and theme registration.

## Task 1: Add Failing Palette Tests

**Files:**
- Create: `Tests/CosmoOSTests/ThemePaletteTests.swift`

- [ ] **Step 1: Create the failing tests**

Create `Tests/CosmoOSTests/ThemePaletteTests.swift`:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import CosmoOS

final class ThemePaletteTests: XCTestCase {
    override func tearDown() {
        DS.palette = GreenhousePalette()
        super.tearDown()
    }

    func testCodexMonoThemeIsRegistered() {
        XCTAssertTrue(CosmoAppTheme.allCases.contains(.codexMono))
        XCTAssertEqual(CosmoAppTheme.codexMono.displayName, "Codex Mono")
        XCTAssertFalse(CosmoAppTheme.codexMono.isDark)
    }

    func testCodexMonoPaletteUsesPremiumMonochromeChrome() {
        let palette = CodexMonoPalette()

        assertColor(palette.bg, equalsHex: "FDFDFC")
        assertColor(palette.surface, equalsHex: "F3F3F4")
        assertColor(palette.surfaceElevated, equalsHex: "FFFFFF")
        assertColor(palette.text, equalsHex: "1F2024")
        assertColor(palette.textSecondary, equalsHex: "5F6068")
        assertColor(palette.accent, equalsHex: "1F2024")
        assertColor(palette.borderSubtle, equalsHex: "EDEDEF")
    }

    func testCodexMonoKeepsSemanticSignalColorsDifferentiated() {
        let palette = CodexMonoPalette()

        assertColor(palette.green, equalsHex: "2F7D5B")
        assertColor(palette.orange, equalsHex: "F26A3D")
        assertColor(palette.red, equalsHex: "D92D20")
        assertColor(palette.info, equalsHex: "2563EB")
        assertColor(palette.greenSoft, equalsHex: "EAF6EF")
        assertColor(palette.orangeSoft, equalsHex: "FFF1EA")
        assertColor(palette.redSoft, equalsHex: "FDEDEC")
        assertColor(palette.infoSoft, equalsHex: "EAF1FF")
    }

    func testCodexMonoKeepsDocumentSurfacesLight() {
        DS.palette = CodexMonoPalette()

        assertColor(DS.documentSurface, equalsHex: "FFFFFF")
        assertColor(DS.documentText, equalsHex: "1F2024")
        assertColor(DS.documentBorderSubtle, equalsHex: "EDEDEF")
    }

    private func assertColor(_ color: Color, equalsHex hex: String, file: StaticString = #filePath, line: UInt = #line) {
        assertColor(NSColor(color), equalsHex: hex, file: file, line: line)
    }

    private func assertColor(_ color: NSColor?, equalsHex hex: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let rgb = color?.usingColorSpace(.sRGB) else {
            XCTFail("Expected an sRGB color", file: file, line: line)
            return
        }

        let expected = hexRGB(hex)
        XCTAssertEqual(rgb.redComponent, expected.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.greenComponent, expected.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.blueComponent, expected.blue, accuracy: 0.001, file: file, line: line)
    }

    private func hexRGB(_ hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/ThemePaletteTests test
```

Expected: FAIL with compiler errors for missing `CodexMonoPalette` and `.codexMono`.

## Task 2: Implement the Codex Mono Palette

**Files:**
- Create: `Core/Theming/CodexMonoPalette.swift`

- [ ] **Step 1: Add the palette**

Create `Core/Theming/CodexMonoPalette.swift`:

```swift
// CosmoOS/Core/Theming/CodexMonoPalette.swift
// Codex-inspired light theme: white workspace, neutral chrome, charcoal accent.

import SwiftUI

struct CodexMonoPalette: ThemePalette {

    // Surfaces
    let bg = Color(hex: "FDFDFC")
    let surface = Color(hex: "F3F3F4")
    let surfaceElevated = Color(hex: "FFFFFF")
    let surfaceCard = Color(hex: "FFFFFF")
    let canvas = Color(hex: "F7F7F8")
    let surfaceHover = Color(hex: "EDEDEF")

    // Text
    let text = Color(hex: "1F2024")
    let textSecondary = Color(hex: "5F6068")
    let textMuted = Color(hex: "8B8D94")
    let textOnAccent = Color.white

    // Accent
    let accent = Color(hex: "1F2024")
    let accentHover = Color(hex: "000000")
    var accentGlow: Color { Color.black.opacity(0.08) }
    let accentSoft = Color(hex: "F1F1F2")

    // Status and semantic signals
    let green = Color(hex: "2F7D5B")
    var greenGlow: Color { Color(hex: "2F7D5B").opacity(0.12) }
    let orange = Color(hex: "F26A3D")
    let red = Color(hex: "D92D20")
    let info = Color(hex: "2563EB")
    let greenSoft = Color(hex: "EAF6EF")
    let orangeSoft = Color(hex: "FFF1EA")
    let redSoft = Color(hex: "FDEDEC")
    let infoSoft = Color(hex: "EAF1FF")

    // Akashic Codex - neutralized for monochrome chrome
    let gilt = Color(hex: "6F7178")
    let giltSoft = Color(hex: "F2F2F3")
    let giltMuted = Color(hex: "A3A4AA")
    let vellum = Color(hex: "F8F8F8")
    let vellumDeep = Color(hex: "F1F1F2")
    let inkWash = Color(hex: "1F2024")
    let inkFaded = Color(hex: "6D6E76")
    let sepiaBorder = Color(hex: "E5E5E7")
    let sepiaSubtle = Color(hex: "EEEEF0")

    // Borders
    let border = Color(hex: "E2E2E4")
    let borderSubtle = Color(hex: "EDEDEF")
    let borderActive = Color(hex: "C7C7CB")
    var focusRing: Color { Color.black.opacity(0.28) }

    // Glass
    var glassCardFill: Color { Color.white.opacity(0.72) }
    var glassInputFill: Color { Color.white.opacity(0.86) }
    var glassInputFillFocused: Color { Color.white.opacity(0.95) }
    var glassSectionFill: Color { Color(hex: "F7F7F8").opacity(0.55) }
    var glassBorder: Color { Color.black.opacity(0.07) }
    var glassBorderFocused: Color { Color.black.opacity(0.30) }

    // Metadata
    let name = "Codex Mono"
    let icon = "circle.lefthalf.filled"
    let isDark = false
}
```

- [ ] **Step 2: Run the failing tests again**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/ThemePaletteTests test
```

Expected: still FAIL because `.codexMono` is not registered and the new Swift file is not yet in the Xcode target.

## Task 3: Register the Theme

**Files:**
- Modify: `Core/Theming/ThemeManager.swift`
- Modify: `CosmoOS.xcodeproj/project.pbxproj`

- [ ] **Step 1: Register the enum case**

Modify `Core/Theming/ThemeManager.swift` so `CosmoAppTheme` includes the new case after `.greenhouse`:

```swift
enum CosmoAppTheme: String, CaseIterable, Identifiable {
    case greenhouse
    case codexMono
    case midnightStudy
    case nordicFrost
    case terracotta
    case obsidian
```

Update the palette switch:

```swift
var palette: ThemePalette {
    switch self {
    case .greenhouse: GreenhousePalette()
    case .codexMono: CodexMonoPalette()
    case .midnightStudy: MidnightStudyPalette()
    case .nordicFrost: NordicFrostPalette()
    case .terracotta: TerracottaPalette()
    case .obsidian: ObsidianPalette()
    }
}
```

Update the display name switch:

```swift
var displayName: String {
    switch self {
    case .greenhouse: "Greenhouse"
    case .codexMono: "Codex Mono"
    case .midnightStudy: "Midnight Study"
    case .nordicFrost: "Nordic Frost"
    case .terracotta: "Terracotta"
    case .obsidian: "Obsidian"
    }
}
```

Update the tagline switch:

```swift
var tagline: String {
    switch self {
    case .greenhouse: "Morning coffee in a sunlit studio"
    case .codexMono: "Black and white workspace with colored signal cues"
    case .midnightStudy: "Late-night deep work by lamplight"
    case .nordicFrost: "Scandinavian clarity on a winter morning"
    case .terracotta: "Mediterranean creative studio at golden hour"
    case .obsidian: "Deep focus cave with electric clarity"
    }
}
```

- [ ] **Step 2: Add the new Swift file to the Xcode target**

Modify `CosmoOS.xcodeproj/project.pbxproj` by adding `CodexMonoPalette.swift` to:

- the `PBXBuildFile` section
- the `PBXFileReference` section
- the `Theming` group next to the other palette files
- the `CosmoOS` target `Sources` build phase

Follow the existing `GreenhousePalette.swift`, `NordicFrostPalette.swift`, `TerracottaPalette.swift`, `MidnightStudyPalette.swift`, and `ObsidianPalette.swift` patterns.

- [ ] **Step 3: Verify project membership**

Run:

```bash
rg -n "CodexMonoPalette.swift|codexMono|Codex Mono" Core/Theming Tests/CosmoOSTests CosmoOS.xcodeproj/project.pbxproj
```

Expected: output shows the new palette file, ThemeManager registrations, tests, and project references.

- [ ] **Step 4: Run the palette tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/ThemePaletteTests test
```

Expected: PASS.

## Task 4: Build And Visual QA

**Files:**
- No expected code changes unless QA reveals an actual hard-coded theme leak.

- [ ] **Step 1: Build the app**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: build succeeds.

- [ ] **Step 2: Launch and switch to Codex Mono**

Open the app and use `Settings > Appearance > Codex Mono`.

Expected:

- Settings preview card appears for `Codex Mono`.
- Selecting it persists `cosmoTheme=codexMono`.
- The app stays in light color scheme.

- [ ] **Step 3: Check the key surfaces against the screenshots**

Review these surfaces:

- Command Center / Today dashboard
- settings theme picker
- Command-K or Codex-style floating input surfaces
- a document/editor surface
- surfaces that use distinct semantic colors, including sidebar icons, habit/category icons, timers, warnings, errors, and info states

Expected visual result:

- main workspace reads as white, not parchment
- side panels read as cool neutral gray, not brown-gray
- borders are present but quiet
- primary action chrome is charcoal/black
- semantic icon/status colors still appear where they communicate meaning, including blue, orange, red, yellow, green, and entity colors
- Greenhouse still looks unchanged when selected again

- [ ] **Step 4: Keep any polish scoped**

If visual QA shows brown leaking in Codex Mono through `DS.gilt`, `DS.vellum`, `DS.sepiaBorder`, or related document tokens, adjust only `CodexMonoPalette.swift` token values and update `ThemePaletteTests.swift` expected hex values.

Do not change `GreenhousePalette.swift`, global typography, spacing, radii, or command-center layout in this theme pass.

## Task 5: Final Verification And Commit

**Files:**
- All implementation files from Tasks 1-3.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug -only-testing:CosmoOSTests/ThemePaletteTests -only-testing:CosmoOSTests/DocumentPaperThemeTests test
```

Expected: PASS.

- [ ] **Step 2: Run a full debug build**

Run:

```bash
xcodebuild -project CosmoOS.xcodeproj -scheme CosmoOS -configuration Debug build
```

Expected: PASS.

- [ ] **Step 3: Review changed files**

Run:

```bash
git diff -- Core/Theming/CodexMonoPalette.swift Core/Theming/ThemeManager.swift Tests/CosmoOSTests/ThemePaletteTests.swift CosmoOS.xcodeproj/project.pbxproj
```

Expected: diff contains only the new palette, registration, tests, and Xcode project membership.

- [ ] **Step 4: Commit**

Run:

```bash
git add Core/Theming/CodexMonoPalette.swift Core/Theming/ThemeManager.swift Tests/CosmoOSTests/ThemePaletteTests.swift CosmoOS.xcodeproj/project.pbxproj
git commit -m "feat: add Codex Mono theme"
```

Expected: commit succeeds.

## Self-Review

- Spec coverage: the plan adds a new black-and-white Codex-inspired chrome theme, preserves existing themes, keeps semantic/icon colors available where they communicate meaning, and includes testing plus visual QA.
- Placeholder scan: no implementation step depends on an undefined file or unnamed follow-up.
- Type consistency: `CodexMonoPalette`, `.codexMono`, `Codex Mono`, and `ThemePaletteTests` are named consistently across tasks.
- Scope check: this is one focused theme addition; broader Greenhouse redesign and dashboard layout changes are intentionally out of scope.
