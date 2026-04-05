// CosmoOS/Data/Models/Codex/CodexWalkthrough.swift
// Full post walkthrough with slide-by-slide Content Physics breakdown.
// Stored in the `structured` JSON field of a `.codexWalkthrough` Atom.

import Foundation

struct CodexWalkthrough: Codable, Sendable, Equatable, Identifiable {
    var id: String { postReference }

    let postReference: String
    let postTitle: String
    let creatorName: String?
    let dominantFrame: String?
    let arcShape: String?
    let whySelected: String?
    let slides: [WalkthroughSlide]
    let transitions: [WalkthroughTransition]
    let rsvTrajectory: [WalkthroughRSVPoint]?
    let physicsEvents: WalkthroughPhysicsEvents?
    let compositionLesson: String?
    let readerJourney: [WalkthroughReaderState]?
    let longRangeBonds: [WalkthroughBond]?
    let echoPatterns: [WalkthroughEcho]?
    let deliberateAbsences: [WalkthroughAbsence]?
    let callbackChains: [WalkthroughCallback]?
    let antimatter: [String]?
    let theFabric: String?
    let sourceSwipeUUID: String?
}

struct WalkthroughSlide: Codable, Sendable, Equatable, Identifiable {
    var id: Int { slideNumber }

    let slideNumber: Int
    let text: String?
    let speechAct: String?
    let readerDeltas: [String]
    let frame: String?
    let distance: String?
    let techniques: [WalkthroughTechnique]
    let proofTypes: [String]
    let motivations: [String]
    let compressions: [String]
    let whyThisSlideWorks: String?
}

struct WalkthroughTechnique: Codable, Sendable, Equatable {
    let canonicalName: String
    let why: String?
}

struct WalkthroughTransition: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(fromSlide)-\(toSlide)" }

    let fromSlide: Int
    let toSlide: Int
    let transitionType: String
    let explanation: String?
}

struct WalkthroughRSVPoint: Codable, Sendable, Equatable, Identifiable {
    var id: Int { afterSlide }

    let afterSlide: Int
    let openLoopCount: Int?
    let trustLevel: String?
    let tensionLevel: String?
    let frame: String?
    let energyBalance: String?
}

struct WalkthroughPhysicsEvents: Codable, Sendable, Equatable {
    let symmetryBreak: PhysicsEventDetail?
    let phaseTransition: PhysicsEventDetail?
    let energyResolution: PhysicsEventDetail?
    let peakGravity: PhysicsEventDetail?
}

struct PhysicsEventDetail: Codable, Sendable, Equatable {
    let slideNumber: Int?
    let description: String?
}

struct WalkthroughReaderState: Codable, Sendable, Equatable, Identifiable {
    var id: Int { afterSlide }

    let afterSlide: Int
    let dominantEmotion: String?
    let investmentLevel: String?
    let activeQuestions: [String]?
    let prediction: String?
}

struct WalkthroughBond: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(setupSlide)-\(payoffSlide)" }

    let setupSlide: Int
    let payoffSlide: Int
    let planted: String?
    let harvested: String?
}

struct WalkthroughEcho: Codable, Sendable, Equatable, Identifiable {
    var id: String { element }

    let element: String
    let positions: [Int]?
    let transformation: String?
}

struct WalkthroughAbsence: Codable, Sendable, Equatable, Identifiable {
    var id: String { what }

    let what: String
    let effect: String?
}

struct WalkthroughCallback: Codable, Sendable, Equatable, Identifiable {
    var id: String { element }

    let element: String
    let appearances: [WalkthroughCallbackAppearance]
    let transformationArc: String?
}

struct WalkthroughCallbackAppearance: Codable, Sendable, Equatable {
    let slide: Int
    let meaning: String?
}
