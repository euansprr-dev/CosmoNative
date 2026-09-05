import SwiftUI

// MARK: - The cast

enum Companion: String, CaseIterable, Identifiable, Codable {
    case sprout
    case fern
    case monstera
    case cactus
    case mushroom
    case snail
    case bee
    case moth
    case sun
    case moon
    case wateringCan
    case paperPlane

    var id: String { rawValue }

    /// The companion's given name — picker-only charm, never chrome.
    var name: String {
        switch self {
        case .sprout: return "Pip"
        case .fern: return "Fiddle"
        case .monstera: return "Delia"
        case .cactus: return "Otto"
        case .mushroom: return "Morel"
        case .snail: return "Juniper"
        case .bee: return "Clementine"
        case .moth: return "Luna"
        case .sun: return "Sol"
        case .moon: return "Sable"
        case .wateringCan: return "Wallace"
        case .paperPlane: return "Scout"
        }
    }

    var species: String {
        switch self {
        case .sprout: return "the sprout"
        case .fern: return "the fern"
        case .monstera: return "the monstera"
        case .cactus: return "the cactus"
        case .mushroom: return "the mushroom"
        case .snail: return "the snail"
        case .bee: return "the bee"
        case .moth: return "the moth"
        case .sun: return "the sun"
        case .moon: return "the moon"
        case .wateringCan: return "the watering can"
        case .paperPlane: return "the paper plane"
        }
    }

    /// One line of character — the picker's serif whisper.
    var bio: String {
        switch self {
        case .sprout: return "Small beginnings."
        case .fern: return "Unfurls in its own time."
        case .monstera: return "Grows toward the light."
        case .cactus: return "Thrives on very little."
        case .mushroom: return "Comfortable in the shade."
        case .snail: return "Slow is smooth."
        case .bee: return "Busy, never rushed."
        case .moth: return "Drawn to bright ideas."
        case .sun: return "Shows up every day."
        case .moon: return "Best work after dark."
        case .wateringCan: return "Keeper of small rituals."
        case .paperPlane: return "Already off on an errand."
        }
    }

    var greeting: String {
        switch self {
        case .sprout: "Something good is taking root."
        case .fern: "We’ll unfold this together."
        case .monstera: "There’s room to grow here."
        case .cactus: "A little care goes a long way."
        case .mushroom: "Big ideas. Cozy little corner."
        case .snail: "No rush. I’m coming with you."
        case .bee: "A little buzz, a little brilliance."
        case .moth: "Found you. Follow the bright idea."
        case .sun: "A little light for your day."
        case .moon: "Quiet company, bright possibilities."
        case .wateringCan: "Here for the little daily things."
        case .paperPlane: "Where shall we wander next?"
        }
    }

    func reply(to response: CompanionResponse) -> String {
        guard response == .celebrate else { return response.message }
        return switch self {
        case .sprout: "Another little leaf. Look what you made happen."
        case .fern: "A little more unfolded today. That’s yours."
        case .monstera: "Making room for what comes next. Nicely grown."
        case .cactus: "Small effort, strong roots. You did it."
        case .mushroom: "Something good grew in our little corner."
        case .snail: "We got there. Slow is still forward."
        case .bee: "One sweet little win, gathered."
        case .moth: "That bright idea became something real."
        case .sun: "There it is. Your little ray of progress."
        case .moon: "Quiet work still shines. Look at that."
        case .wateringCan: "A little care, a little growth. It adds up."
        case .paperPlane: "A little further than we were before."
        }
    }

    /// Primary ink — also drives the badge wash.
    var tint: Color {
        switch self {
        case .sprout: return Color(hex: "7FB069")
        case .fern: return Color(hex: "4A8B72")
        case .monstera: return Color(hex: "3E7C5B")
        case .cactus: return Color(hex: "7FA37A")
        case .mushroom: return Color(hex: "C1694F")
        case .snail: return Color(hex: "B08C5A")
        case .bee: return Color(hex: "E0A83C")
        case .moth: return Color(hex: "A3B899")
        case .sun: return Color(hex: "E8B84B")
        case .moon: return Color(hex: "6B7BA8")
        case .wateringCan: return Color(hex: "8FA5A8")
        case .paperPlane: return Color(hex: "8FA8C9")
        }
    }

    /// Deep ink for the second tone.
    var shade: Color {
        switch self {
        case .sprout: return Color(hex: "2D6A4F")
        case .fern: return Color(hex: "2F5D4A")
        case .monstera: return Color(hex: "2B5741")
        case .cactus: return Color(hex: "567553")
        case .mushroom: return Color(hex: "8F4A37")
        case .snail: return Color(hex: "7E633D")
        case .bee: return Color(hex: "3A342A")
        case .moth: return Color(hex: "5F7561")
        case .sun: return Color(hex: "D08A2E")
        case .moon: return Color(hex: "4A5680")
        case .wateringCan: return Color(hex: "5F787B")
        case .paperPlane: return Color(hex: "5B84B0")
        }
    }

    /// Cream/soft third tone for spots, wings, drops.
    var detail: Color {
        switch self {
        case .mushroom, .snail: return Color(hex: "F3EDE4")
        case .bee: return Color(hex: "FAF7EF")
        case .moth: return Color(hex: "F3EDE4")
        case .moon: return Color(hex: "D9B44A")
        case .cactus: return Color(hex: "E8909C")
        case .wateringCan: return Color(hex: "8FBFD9")
        case .paperPlane: return Color(hex: "EDF2F8")
        default: return Color(hex: "F3EDE4")
        }
    }

    var accessibilityDescription: String {
        "\(name) \(species)"
    }
}

// MARK: - Vitality (the living part — fed by the focus streak)

/// How the companion carries itself today. Never punitive: the worst state
/// is simply "resting". Raw values are stable for the demo launch flag.
enum CompanionVitality: String {
    /// The everyday state.
    case resting
    /// Today's focus goal is met — a quiet accent ring.
    case thriving
    /// A 7-day focus streak — the ring turns gilt and shimmers once.
    case radiant
    /// A 30-day focus streak — the gilt ring earns a small star.
    case luminous
}

// The compact identity mark. Large portraits deliberately have no enclosing badge.
struct CompanionMark: View {
    let companion: Companion
    var size: CGFloat = 32
    var vitality: CompanionVitality = .resting
    var growth: CompanionGrowth? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var delighted = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        CompanionPortrait(companion: companion, growth: growth ?? CompanionStore.shared.growth, size: size, isDelighted: delighted)
            .background(companion.tint.opacity(0.08), in: Circle())
            .overlay {
                Circle().strokeBorder(ringColor, lineWidth: max(0.6, size / 45))
            }
            .overlay(alignment: .topTrailing) {
                if vitality == .luminous {
                    CompanionSparkle(color: DS.gilt).frame(width: size * 0.22, height: size * 0.22)
                }
            }
            .scaleEffect(delighted && !reduceMotion ? 1.06 : 1)
            .onChange(of: CompanionStore.shared.momentID) { _, _ in react() }
            .onChange(of: vitality) { _, next in if next != .resting { react() } }
            .onDisappear { resetTask?.cancel() }
            .accessibilityHidden(true)
    }

    private func react() {
        resetTask?.cancel()
        withAnimation(reduceMotion ? nil : ProMotionSprings.bouncy) { delighted = true }
        resetTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            withAnimation(reduceMotion ? nil : ProMotionSprings.gentle) { delighted = false }
        }
    }

    private var ringColor: Color {
        switch vitality {
        case .resting: DS.sepiaBorder.opacity(0.5)
        case .thriving: DS.accent.opacity(0.45)
        case .radiant, .luminous: DS.gilt.opacity(0.7)
        }
    }
}

struct CompanionSparkle: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let path = Path { p in
                p.move(to: CGPoint(x: w / 2, y: 0))
                p.addQuadCurve(to: CGPoint(x: w, y: h / 2), control: CGPoint(x: w * 0.6, y: h * 0.4))
                p.addQuadCurve(to: CGPoint(x: w / 2, y: h), control: CGPoint(x: w * 0.6, y: h * 0.6))
                p.addQuadCurve(to: CGPoint(x: 0, y: h / 2), control: CGPoint(x: w * 0.4, y: h * 0.6))
                p.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: w * 0.4, y: h * 0.4))
            }
            context.fill(path, with: .color(color))
        }
    }
}
