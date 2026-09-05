import SwiftUI

enum CompanionExpression: String, CaseIterable, Identifiable, Codable {
    case resting, attentive, working, speaking, reviewing, celebrating, restingFocus
    var id: Self { self }
    var title: String {
        switch self {
        case .resting: return "At home"
        case .attentive: return "Hello"
        case .working: return "Thinking"
        case .speaking: return "A bright idea"
        case .reviewing: return "Ready to review"
        case .celebrating: return "A little celebration"
        case .restingFocus: return "Quiet company"
        }
    }
}

/// A small authored performance for each state change. There is no idle clock,
/// repeatForever, or token-driven animation. The static expression stays useful
/// with Reduce Motion and while the application is in the background.
struct CompanionCharacterView: View {
    let companion: Companion
    var growth: CompanionGrowth = .beginning
    var expression: CompanionExpression = .resting
    var size: CGFloat = 64
    var quiet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var accentPose = false
    @State private var settleTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            CompanionPortrait(companion: companion, growth: growth, size: size, expression: expression)
                .id(growth)
                .transition(.opacity)
        }
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .scaleEffect(x: accentPose && canMove ? 1.025 : 1, y: accentPose && canMove ? 0.985 : 1, anchor: .bottom)
            .offset(y: expression == .celebrating && accentPose && canMove ? -size * 0.035 : 0)
            .animation(canMove ? ProMotionSprings.bouncy : nil, value: accentPose)
            .animation(canMove ? ProMotionSprings.gentle : nil, value: growth)
            .onChange(of: expression) { _, _ in performPose() }
            .onChange(of: growth) { _, _ in performPose() }
            .onDisappear { settleTask?.cancel() }
            .accessibilityHidden(true)
    }

    private var canMove: Bool { !quiet && !reduceMotion && scenePhase == .active }
    private var tilt: Double {
        guard canMove, accentPose else { return 0 }
        switch companion {
        case .snail, .wateringCan: return -3
        case .paperPlane, .bee, .moth: return -5
        case .monstera, .fern: return 3
        default: return -2
        }
    }
    private func performPose() {
        settleTask?.cancel()
        guard canMove else { accentPose = false; return }
        accentPose = true
        settleTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(expression == .celebrating ? 700 : 360)) } catch { return }
            accentPose = false
        }
    }
}
