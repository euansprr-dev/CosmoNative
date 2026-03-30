// CosmoOS/Data/Models/ContentPhysicsProfile.swift
// Swift data model mirroring the TypeScript QuarkProfile
// Parsed from atom.structured.contentPhysics JSON

import Foundation

struct ContentPhysicsProfile: Codable {
    let version: Int?
    let extractedAt: String?
    let extractedBy: String?

    // Pass 1: Per-slide quarks
    let slideQuarks: [SlideQuark]?

    // Pass 2: Transitions
    let transitions: [QuarkTransition]?

    // Pass 3: Arc quarks
    let arcQuarks: ArcQuarks?

    // Pass 4: RSV trajectory
    let rsv: RSVData?

    // Pass 5: Physics events
    let physicsEvents: PhysicsEvents?

    // Pass 6: Novel discoveries
    let novelDiscoveries: [String]?

    // Pass 7: Long-range interactions
    let longRangeInteractions: LongRangeInteractions?

    // Pass 8: Rhythm and pacing
    let rhythm: RhythmData?

    // Pass 9: Complete reader simulation
    let readerSimulation: [ReaderState]?

    // Pass 10: Deep fabric synthesis
    let deepFabric: String?
}

// MARK: - Slide Quarks (Pass 1)

struct SlideQuark: Codable, Identifiable {
    var id: Int { slideNumber }
    let slideNumber: Int
    let text: String?
    let speechAct: QuarkMechanism
    let readerDeltas: [QuarkMechanism]?
    let proofType: QuarkMechanism?
    let motivation: QuarkMechanism?
    let compression: CompressionQuark?
}

struct QuarkMechanism: Codable {
    let type: String?
    let mechanism: String?
}

struct CompressionQuark: Codable {
    let type: String
    let size: String?
    let mechanism: String?
}

// MARK: - Transitions (Pass 2)

struct QuarkTransition: Codable, Identifiable {
    var id: String { "\(from)-\(to)" }
    let from: Int
    let to: Int
    let type: String
    let mechanism: String?
    let swapTestPasses: Bool?
    let doubleHelix: Bool?
    let doubleHelixDetail: String?
}

// MARK: - Arc Quarks (Pass 3)

struct ArcQuarks: Codable {
    let shape: String?
    let winLossReversals: Int?
    let tensionPeaks: [Int]?
    let sparseDensePattern: String?
    let internalExternalTension: InternalExternalTension?
}

struct InternalExternalTension: Codable {
    let present: Bool?
    let peakSlide: Int?
    let description: String?
}

// MARK: - RSV (Pass 4)

struct RSVData: Codable {
    let trajectoryPoints: [RSVPoint]?
}

struct RSVPoint: Codable, Identifiable {
    var id: Int { afterSlide }
    let afterSlide: Int
    let openLoops: OpenLoops?
    let trust: String?
    let tension: TensionState?
    let patternExpectation: String?
    let frame: String?
    let energyBalance: String?
}

struct OpenLoops: Codable {
    let count: Int
    let loops: [String]?
}

struct TensionState: Codable {
    let level: String?
    let type: String?
}

// MARK: - Physics Events (Pass 5)

struct PhysicsEvents: Codable {
    let symmetryBreak: SymmetryBreak?
    let phaseTransition: PhaseTransition?
    let energyResolution: EnergyResolution?
    let peakGravity: PeakGravity?
}

struct SymmetryBreak: Codable {
    let slideNumber: Int?
    let patternEstablished: String?
    let whatBreaks: String?
    let whyDevastating: String?
}

struct PhaseTransition: Codable {
    let slideNumber: Int?
    let frameBefore: String?
    let frameAfter: String?
    let recontextualization: String?
}

struct EnergyResolution: Codable {
    let proportional: Bool?
    let loopsClosed: [LoopClosure]?
    let loopsUnclosed: [String]?
    let assessment: String?
}

struct LoopClosure: Codable {
    let loop: String?
    let closedAtSlide: Int?
}

struct PeakGravity: Codable {
    let slideNumber: Int?
    let activeLoops: Int?
    let coincidesWithTransition: Bool?
}

// MARK: - Long-Range Interactions (Pass 7)

struct LongRangeInteractions: Codable {
    let setupPayoffBonds: [SetupPayoffBond]?
    let echoPatterns: [EchoPattern]?
    let interferences: [Interference]?
    let deliberateAbsences: [DeliberateAbsence]?
    let callbackChains: [CallbackChain]?
}

struct SetupPayoffBond: Codable, Identifiable {
    var id: String { "\(setupSlide)-\(payoffSlide)" }
    let setupSlide: Int
    let payoffSlide: Int
    let distance: Int?
    let planted: String?
    let harvested: String?
}

struct EchoPattern: Codable, Identifiable {
    var id: String { quarkType }
    let quarkType: String
    let positions: [Int]?
    let transformation: String?
}

struct Interference: Codable, Identifiable {
    var id: String { forces.joined(separator: "+") }
    let slides: [Int]?
    let forces: [String]
    let emergentEffect: String?
}

struct DeliberateAbsence: Codable, Identifiable {
    var id: String { what }
    let what: String
    let slides: [Int]?
    let effect: String?
}

struct CallbackChain: Codable, Identifiable {
    var id: String { element }
    let element: String
    let appearances: [CallbackAppearance]?
    let transformationArc: String?
}

struct CallbackAppearance: Codable {
    let slide: Int
    let meaning: String?
}

// MARK: - Rhythm (Pass 8)

struct RhythmData: Codable {
    let densityWaveform: [Double]?  // Model may output floats
    let energyCurve: [Double]?
    let informationRate: [Double]?
    let silenceSlides: [Int]?
    let momentumMechanism: String?
    let pacingPattern: String?
}

// MARK: - Reader Simulation (Pass 9)

struct ReaderState: Codable, Identifiable {
    var id: Int { afterSlide }
    let afterSlide: Int
    let activeQuestions: [String]?
    let builtAssumptions: [String]?
    let prediction: String?
    let dominantEmotion: String?
    let investmentLevel: String?
}

// MARK: - Atom Extension for Parsing

extension Atom {
    var contentPhysicsProfile: ContentPhysicsProfile? {
        guard let structured = structured,
              let data = structured.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let physicsJSON = json["contentPhysics"],
              let physicsData = try? JSONSerialization.data(withJSONObject: physicsJSON) else {
            return nil
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ContentPhysicsProfile.self, from: physicsData)
        } catch {
            print("⚠️ ContentPhysicsProfile decode failed: \(error)")
            // Try to at least confirm the data exists even if decode fails
            if let dict = try? JSONSerialization.jsonObject(with: physicsData) as? [String: Any] {
                print("⚠️ contentPhysics keys present: \(dict.keys.sorted().joined(separator: ", "))")
            }
            return nil
        }
    }
}
