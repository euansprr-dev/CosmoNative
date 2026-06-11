// CosmoOS/Canvas/CanvasPlaces.swift
// Places — named, saved camera positions inside a thinkspace.
// Cmd+D captures the current view; jumps fly the camera with a zoom arc
// instead of hard-cutting, so teleporting still reads as travel.

import SwiftUI

// MARK: - Model

/// A saved camera position inside a thinkspace: a canvas-space center point
/// plus zoom. Stored in `ThinkspaceMetadata.places`.
struct CanvasPlace: Codable, Equatable, Identifiable, Sendable {
    let uuid: String
    var name: String
    var centerX: Double
    var centerY: Double
    var zoom: Double
    let createdAt: Date

    var id: String { uuid }

    var center: CGPoint { CGPoint(x: centerX, y: centerY) }

    init(name: String, center: CGPoint, zoom: Double) {
        self.uuid = UUID().uuidString
        self.name = name
        self.centerX = center.x
        self.centerY = center.y
        self.zoom = zoom
        self.createdAt = Date()
    }
}

// MARK: - Capture Card

/// The Cmd+D save card — one field, zero ceremony. Return saves, Esc cancels.
struct PlaceCaptureCard: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            nameField
        }
        .padding(16)
        .frame(width: 320)
        .cosmoGlassPanel(role: .floatingAssistant, cornerRadius: 18)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            fieldFocused = true
            withAnimation(reduceMotion ? .linear(duration: 0.01) : ProMotionSprings.bouncy) {
                appeared = true
            }
        }
        .onExitCommand(perform: onCancel)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(DS.caption)
                .foregroundStyle(DS.accent)
            Text("Save this view")
                .font(DS.caption)
                .tracking(0.3)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var nameField: some View {
        TextField("Place name", text: $name)
            .textFieldStyle(.plain)
            .font(DS.callout)
            .foregroundStyle(DS.text)
            .focused($fieldFocused)
            .onSubmit(onSave)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .dsGlassInput(isFocused: fieldFocused, cornerRadius: 10)
            .accessibilityLabel("Place name")
    }
}

// MARK: - Minimap Place Diamond

/// A place marker on the minimap — a 5pt accent diamond with a name tag on hover.
struct MinimapPlaceDiamond: View {
    let place: CanvasPlace
    let position: CGPoint
    let onJump: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(DS.accent)
            .frame(width: 5, height: 5)
            .rotationEffect(.degrees(45))
            .scaleEffect(isHovered ? 1.6 : 1)
            .overlay(alignment: .top) { nameTag }
            .contentShape(Rectangle().inset(by: -6))
            .position(position)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : ProMotionSprings.hover) { isHovered = hovering }
            }
            .onTapGesture(perform: onJump)
            .help(place.name)
            .accessibilityLabel("Jump to \(place.name)")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var nameTag: some View {
        if isHovered {
            Text(place.name)
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(DS.glassCardFill))
                .overlay(Capsule().strokeBorder(DS.glassBorder, lineWidth: 0.5))
                .fixedSize()
                .offset(y: -20)
                .transition(.opacity)
        }
    }
}
