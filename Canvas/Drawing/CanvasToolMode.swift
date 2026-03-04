// CosmoOS/Canvas/Drawing/CanvasToolMode.swift
// Tool mode enum for canvas drawing tools

import Foundation

enum CanvasToolMode: String, CaseIterable {
    case select
    case shape
    case draw
    case text
    case erase
    case lasso
}

/// Sub-modes for the lasso tool slot — lasso selects blocks, zone draws empty rectangular zones
enum LassoSubMode: String, CaseIterable {
    case lasso
    case zone
}
