// CosmoOS/Data/Models/Codex/CodexElementCategory.swift
// Category taxonomy for the Content Physics periodic table.

import Foundation
import SwiftUI

enum CodexElementCategory: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case speechAct
    case transition
    case readerDelta
    case proofType
    case motivation
    case compression
    case frame
    case distance
    case technique
    case dominantFrame
    case arcShape
    case physicsEvent
    case longRangeInteraction
    case rsvDimension
    case compoundPattern
    case antimatter
    case force
    case law

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speechAct: "Speech Act"
        case .transition: "Transition"
        case .readerDelta: "Reader Delta"
        case .proofType: "Proof Type"
        case .motivation: "Motivation"
        case .compression: "Compression"
        case .frame: "Frame"
        case .distance: "Distance"
        case .technique: "Technique"
        case .dominantFrame: "Dominant Frame"
        case .arcShape: "Arc Shape"
        case .physicsEvent: "Physics Event"
        case .longRangeInteraction: "Long-Range Interaction"
        case .rsvDimension: "RSV Dimension"
        case .compoundPattern: "Compound Pattern"
        case .antimatter: "Antimatter"
        case .force: "Force"
        case .law: "Law"
        }
    }

    var pluralDisplayName: String {
        switch self {
        case .speechAct: "Speech Acts"
        case .transition: "Transitions"
        case .readerDelta: "Reader Deltas"
        case .proofType: "Proof Types"
        case .motivation: "Motivations"
        case .compression: "Compressions"
        case .frame: "Frames"
        case .distance: "Distances"
        case .technique: "Techniques"
        case .dominantFrame: "Dominant Frames"
        case .arcShape: "Arc Shapes"
        case .physicsEvent: "Physics Events"
        case .longRangeInteraction: "Long-Range Interactions"
        case .rsvDimension: "RSV Dimensions"
        case .compoundPattern: "Compound Patterns"
        case .antimatter: "Antimatter"
        case .force: "Forces"
        case .law: "Laws"
        }
    }

    var icon: String {
        switch self {
        case .speechAct: "bubble.left.fill"
        case .transition: "arrow.right.arrow.left"
        case .readerDelta: "heart.fill"
        case .proofType: "checkmark.seal.fill"
        case .motivation: "flame.fill"
        case .compression: "arrow.down.right.and.arrow.up.left"
        case .frame: "viewfinder"
        case .distance: "ruler"
        case .technique: "wrench.and.screwdriver.fill"
        case .dominantFrame: "rectangle.3.group.fill"
        case .arcShape: "waveform.path.ecg"
        case .physicsEvent: "bolt.fill"
        case .longRangeInteraction: "link"
        case .rsvDimension: "chart.line.uptrend.xyaxis"
        case .compoundPattern: "square.stack.3d.up.fill"
        case .antimatter: "xmark.octagon.fill"
        case .force: "tornado"
        case .law: "book.closed.fill"
        }
    }

    var color: Color {
        switch self {
        case .speechAct: Color(hex: "5B84B0")
        case .transition: Color(hex: "6B8CA8")
        case .readerDelta: Color(hex: "C17B5A")
        case .proofType: Color(hex: "5E8C61")
        case .motivation: Color(hex: "B06B6B")
        case .compression: Color(hex: "8B6BAB")
        case .frame: Color(hex: "4A8B72")
        case .distance: Color(hex: "7B8A6E")
        case .technique: Color(hex: "B08C5A")
        case .dominantFrame: Color(hex: "2E86AB")
        case .arcShape: Color(hex: "A23B72")
        case .physicsEvent: Color(hex: "D17B4F")
        case .longRangeInteraction: Color(hex: "4A8B9B")
        case .rsvDimension: Color(hex: "6B6EA8")
        case .compoundPattern: Color(hex: "7B68AE")
        case .antimatter: Color(hex: "B5555A")
        case .force: Color(hex: "C18C5D")
        case .law: Color(hex: "5A6B8A")
        }
    }

    var sortOrder: Int {
        switch self {
        case .speechAct: 0
        case .transition: 1
        case .readerDelta: 2
        case .proofType: 3
        case .motivation: 4
        case .compression: 5
        case .frame: 6
        case .distance: 7
        case .technique: 8
        case .dominantFrame: 9
        case .arcShape: 10
        case .physicsEvent: 11
        case .longRangeInteraction: 12
        case .rsvDimension: 13
        case .compoundPattern: 14
        case .antimatter: 15
        case .force: 16
        case .law: 17
        }
    }
}
