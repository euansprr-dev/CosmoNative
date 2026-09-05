# Build verification — 2026-09-05

The approved app icon is installed in both source asset catalogs. Both catalogs passed standalone Xcode asset compilation with no warnings or errors. PNG dimensions, transparency, metadata, and export checksums passed verification. Generated small icons were visually inspected.

## macOS

The first full Debug build failed because another running build held the shared Xcode build database. A retry after that build finished successfully compiled and linked `AppIcon.icns` and `Assets.car` into the Debug app bundle and processed its icon metadata.

The remaining full Swift compilation was deliberately interrupted after icon verification. Several unrelated builds were still running, the repository contained ongoing code changes, and available disk space had fallen below 4 GiB. A complete macOS application build is therefore **not claimed**.

## iOS

The full Debug simulator build compiled the asset catalog, then failed during Swift compilation:

```text
CosmoiOS/Sources/Shared/CosmoMasthead.swift:36:15:
error: cannot find type 'CosmoIcon' in scope
```

This is a Swift type used by ongoing UI work, unrelated to the `AppIcon` image catalog. Inspection found `CosmoIcon.swift` in the current working tree and project, but absent from the source-file list captured by this build. The source project was changing concurrently. No UI source or project configuration was changed as part of the app-icon installation.

The full iOS application build did **not pass**. No device installation or simulator launch is claimed.

## Evidence

The adjacent compiler logs and asset archive inventories document the successful icon checks. `cosmo-evergreen-*-summary.txt` records the full-build results. Full raw logs remain at `/tmp/cosmo-evergreen-macos-build.log`, `/tmp/cosmo-evergreen-macos-retry.log`, and `/tmp/cosmo-evergreen-ios-build.log`.
