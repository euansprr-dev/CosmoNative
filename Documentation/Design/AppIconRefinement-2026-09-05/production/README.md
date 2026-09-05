# 05 Evergreen — production app icons

Approved for macOS and iOS on 2026-09-05. The artwork is unchanged from `../svg/05-evergreen.svg`: forest background, ivory orbit and veined leaf, sage crossing orbit.

## Installed catalogs

- macOS: `Resources/Assets.xcassets/AppIcon.appiconset` in the CosmoOS-Swift repository. Seven physical PNG sizes (16, 32, 64, 128, 256, 512, 1024 pixels) fill the ten 1x/2x catalog slots.
- iOS: `CosmoiOS/Resources/Assets.xcassets/AppIcon.appiconset` in the CosmoOS-iOS repository. The opaque 1024px PNG is a byte-for-byte copy of `../png/05-evergreen-1024.png`. Xcode generates device sizes.

Both projects already select `AppIcon` in Debug and Release; no project configuration changes were needed.

## Platform exports

The iOS artwork remains a full square for the system's mask. The legacy macOS catalog uses a transparent 1024px canvas with an 832px continuous rounded square inset by 96px. This gives the icon conventional Dock proportions without adding depth or changing the mark.

`export-macos.swift` renders the macOS master with SwiftUI's continuous rounded rectangle (188px radius). Compile it with `swiftc -parse-as-library`, then pass `../png/05-evergreen-4096.png` and the destination PNG as its two arguments. The smaller catalog assets are Lanczos downsampled from that 1024px export.

## Verification

- Catalog filenames, physical pixel sizes, opacity, and approved-source identity checked.
- Both catalogs compiled successfully with Xcode 26.1.1 `actool`, without warnings or errors.
- The macOS compiled asset archive contains all ten requested size/scale renditions.
- Generated icon metadata selects `AppIcon` on both platforms.
- Xcode's generated 256px macOS and 120px iOS icons were visually inspected; copies are alongside this file.
- `asset-manifest.json` records SHA-256 checksums for the eight installed PNG files. Compiler logs, metadata, and asset archive inventories are included.

Full app build results are recorded separately in `build-verification.md`.
