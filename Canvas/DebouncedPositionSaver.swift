// CosmoOS/Canvas/DebouncedPositionSaver.swift
//
// DEPRECATED — June 2026 data-safety pass.
//
// This file previously contained a `DebouncedPositionSaver` class and a
// `DebouncedDragWrapper` view that were never wired into any call site (dead
// code per the data-safety audit, RC5). Keeping unwired persistence machinery
// around risked someone adopting it instead of the real path.
//
// Canvas block position/size persistence lives in `SpatialEngine`:
//   - `updateBlockPosition(_:position:)` / `updateBlockGeometry(_:position:size:)`
//     perform fire-and-forget writes and track in-flight values.
//   - In-flight writes are flushed synchronously at app termination via
//     `DirtyEditorRegistry` (see SpatialEngine's init/`flushPendingGeometryWritesSync`).
//
// The file is intentionally left as a tombstone (it is still referenced by
// the Xcode project); do not add new code here.

import Foundation

enum DebouncedPositionSaverTombstone {
    // Intentionally empty.
}
