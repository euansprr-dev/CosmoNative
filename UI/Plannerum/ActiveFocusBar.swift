// CosmoOS/UI/Plannerum/ActiveFocusBar.swift
// Plannerum Active Focus Bar - Bottom dock with timer and XP integration
// PLANERIUM_SPEC.md Section 2.5 compliant

import SwiftUI
import Combine

// MARK: - Active Focus Bar

/// The bottom dock in Plannerum showing active focus block.
///
/// From PLANERIUM_SPEC.md Section 2.5:
/// ```
/// POSITION & SIZE
/// ├── Position: Fixed at bottom of Planerium
/// ├── Height: 64pt
/// ├── Width: 100%
/// └── Z-index: Above all other content
///
/// BACKGROUND
/// ├── Fill: rgba(15, 15, 20, 0.95)
/// ├── Blur: 40px Gaussian backdrop
/// ├── Top border: 1px rgba(255,255,255,0.08)
/// └── Glow: subtle block_color @ 10% at top edge
/// ```
public struct ActiveFocusBar: View {

    // MARK: - State

    @StateObject private var viewModel = ActiveFocusBarViewModel()
    @State private var pulsePhase: Double = 0
    @State private var pulseTimerCancellable: AnyCancellable?

    // MARK: - Layout (Spec Section 2.5)

    private enum Layout {
        static let height: CGFloat = 64        // Spec: Height: 64pt
        static let topBorder: CGFloat = 1      // Spec: Top border: 1px
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 10
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Top glow edge (Spec: subtle block_color @ 10%)
            if viewModel.isInFocus, let activeBlock = viewModel.activeBlock {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                activeBlock.blockType.color.opacity(0.15),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 8)
            }

            // Main content
            VStack(spacing: 8) {
                // Top row: Status, block info, timer, XP
                topRow

                // Bottom row: Action buttons
                bottomRow
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
        }
        .frame(height: Layout.height)
        .background(focusBarBackground)
        .onAppear {
            Task {
                await viewModel.loadActiveFocus()
            }
            startPulseAnimation()
        }
        .onDisappear {
            pulseTimerCancellable?.cancel()
            pulseTimerCancellable = nil
        }
    }

    // MARK: - Background (Spec: rgba(15, 15, 20, 0.95) + 40px blur)

    private var focusBarBackground: some View {
        ZStack {
            // Base fill
            Rectangle()
                .fill(Color(red: 15/255, green: 15/255, blue: 20/255).opacity(0.95))

            // Blur effect
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.3)

            // Top border (Spec: 1px rgba(255,255,255,0.08))
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: Layout.topBorder)
                Spacer()
            }
        }
    }

    // MARK: - Top Row

    private var topRow: some View {
        HStack(spacing: 12) {
            // Left: Status indicator + Block info
            HStack(spacing: 10) {
                // Pulsing status dot (Spec: ● pulsing green dot)
                statusIndicator

                // Block info
                if let activeBlock = viewModel.activeBlock {
                    activeBlockLabel(activeBlock)
                } else if let nextBlock = viewModel.nextBlock {
                    nextBlockLabel(nextBlock)
                } else {
                    noBlockLabel
                }
            }

            Spacer()

            // Timer display (Spec: HH:MM:SS 24pt Mono Bold)
            if viewModel.isInFocus {
                timerDisplay
            }

            // XP Preview (Spec: "+125 XP (projected)" 14pt Mono)
            xpPreview
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        ZStack {
            // Outer pulse glow
            if viewModel.isInFocus {
                Circle()
                    .fill(PlannerumColors.nowMarker.opacity(0.3))
                    .frame(width: 16, height: 16)
                    .scaleEffect(1.0 + 0.2 * sin(pulsePhase))
            }

            // Inner dot
            Circle()
                .fill(
                    viewModel.isInFocus
                        ? PlannerumColors.nowMarker
                        : (viewModel.nextBlock != nil ? PlannerumColors.primary : PlannerumColors.textMuted)
                )
                .frame(width: 8, height: 8)
        }
        .frame(width: 20, height: 20)
    }

    // MARK: - Active Block Label (Spec: "ACTIVE" 10pt Bold green + block info 15pt Semibold)

    private func activeBlockLabel(_ block: ScheduleBlockViewModel) -> some View {
        HStack(spacing: 8) {
            // ACTIVE badge
            Text("ACTIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(PlannerumColors.nowMarker)

            // Separator
            Text("│")
                .font(.system(size: 12))
                .foregroundColor(PlannerumColors.glassBorder)

            // Block type + title (Spec: "Deep Work: [Title]" 15pt Semibold)
            HStack(spacing: 6) {
                Image(systemName: block.blockType.icon)
                    .font(.system(size: 12))
                    .foregroundColor(block.blockType.color)

                Text("\(block.blockType.displayName): \(block.title)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PlannerumColors.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    private func nextBlockLabel(_ block: ScheduleBlockViewModel) -> some View {
        HStack(spacing: 8) {
            Text("NEXT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(PlannerumColors.textMuted)

            Text("at \(PlannerumFormatters.time.string(from: block.startTime))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PlannerumColors.textTertiary)

            HStack(spacing: 4) {
                Image(systemName: block.blockType.icon)
                    .font(.system(size: 11))
                    .foregroundColor(block.blockType.color)

                Text(block.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(PlannerumColors.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var noBlockLabel: some View {
        HStack(spacing: 8) {
            Text("NO ACTIVE BLOCK")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(PlannerumColors.textMuted)

            Text("Schedule or start a block to begin")
                .font(.system(size: 12))
                .foregroundColor(PlannerumColors.textTertiary)
        }
    }

    // MARK: - Timer Display (Spec: 24pt Mono Bold)

    private var timerDisplay: some View {
        let elapsed = viewModel.elapsedTime ?? 0

        return Text(formatDuration(elapsed))
            .font(.system(size: 24, weight: .bold, design: .monospaced))
            .foregroundColor(PlannerumColors.textPrimary)
            .monospacedDigit()
    }

    // MARK: - XP Preview (Spec: "+125 XP (projected)" 14pt Mono)

    private var xpPreview: some View {
        let xpAmount = viewModel.potentialXP
        let isProjected = !viewModel.isInFocus || viewModel.elapsedTime == nil

        return HStack(spacing: 4) {
            Text("+\(xpAmount) XP")
                .font(.system(size: 14, weight: .bold, design: .monospaced))

            if isProjected {
                Text("(projected)")
                    .font(.system(size: 11))
            }
        }
        .foregroundColor(xpAmount > 0 ? PlannerumColors.xpGold : PlannerumColors.textMuted)
    }

    // MARK: - Bottom Row (Action Buttons)

    private var bottomRow: some View {
        HStack(spacing: 12) {
            Spacer()

            if viewModel.isInFocus {
                // Pause button (Spec: Glass secondary, gray text)
                Button(action: { viewModel.pauseFocus() }) {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PlannerumColors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(PlannerumColors.glassSecondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(PlannerumColors.glassBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                // Complete button (Spec: Solid green background, white text)
                Button(action: { viewModel.completeFocus() }) {
                    HStack(spacing: 6) {
                        Text("Complete Block")
                        Text("+\(viewModel.potentialXP) XP")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(PlannerumColors.nowMarker)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Extend button (Spec: Glass secondary, violet text)
                Button(action: { viewModel.extendFocus(minutes: 30) }) {
                    Label("Extend 30m", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PlannerumColors.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(PlannerumColors.glassSecondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(PlannerumColors.primary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

            } else if viewModel.nextBlock != nil {
                // Start Focus button
                Button(action: { viewModel.startFocus() }) {
                    Label("Start Focus", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(PlannerumColors.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func startPulseAnimation() {
        pulseTimerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                pulsePhase += 0.1
            }
    }
}

// MARK: - Active Focus Bar View Model

@MainActor
public class ActiveFocusBarViewModel: ObservableObject {

    @Published public var activeBlock: ScheduleBlockViewModel?
    @Published public var nextBlock: ScheduleBlockViewModel?
    @Published public var isInFocus = false
    @Published public var elapsedTime: TimeInterval?
    @Published public var potentialXP: Int = 0

    private var timerCancellable: AnyCancellable?
    private var focusStartTime: Date?

    public func loadActiveFocus() async {
        do {
            let calendar = Calendar.current
            let now = Date()
            let dayStart = calendar.startOfDay(for: now)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let atoms = try await AtomRepository.shared.fetchAll(type: .scheduleBlock)
                .filter { !$0.isDeleted }

            let todayBlocks = atoms.compactMap { atom -> ScheduleBlockViewModel? in
                guard let metadata = atom.metadataValue(as: ScheduleBlockMetadata.self),
                      let startTimeStr = metadata.startTime,
                      let endTimeStr = metadata.endTime,
                      let startTime = PlannerumFormatters.iso8601.date(from: startTimeStr),
                      let endTime = PlannerumFormatters.iso8601.date(from: endTimeStr),
                      startTime >= dayStart && startTime < dayEnd,
                      !(metadata.isCompleted ?? false)
                else {
                    return nil
                }

                let blockType = TimeBlockType.from(string: metadata.blockType ?? "deep_work")

                let status = metadata.status.flatMap { BlockStatus(rawValue: $0) } ?? .scheduled
                return ScheduleBlockViewModel(
                    id: atom.uuid,
                    title: atom.title ?? "Untitled Block",
                    startTime: startTime,
                    endTime: endTime,
                    blockType: blockType,
                    status: status,
                    isCompleted: metadata.isCompleted ?? false,
                    projectUuid: nil,
                    projectName: nil,
                    linkedAtomIds: atom.linksList.map { $0.uuid }
                )
            }
            .sorted { $0.startTime < $1.startTime }

            // Find active block (current time within block's time range)
            activeBlock = todayBlocks.first { block in
                now >= block.startTime && now <= block.endTime
            }

            // Find next upcoming block
            nextBlock = todayBlocks.first { block in
                block.startTime > now
            }

            // Calculate potential XP
            if let active = activeBlock {
                let durationMinutes = Int(active.duration / 60)
                potentialXP = PlannerumXP.estimateXP(blockType: active.blockType, durationMinutes: durationMinutes)

                // Auto-start if we're within an active block
                if !isInFocus {
                    isInFocus = true
                    focusStartTime = active.startTime
                    startTimer()
                }
            } else if let next = nextBlock {
                let durationMinutes = Int(next.duration / 60)
                potentialXP = PlannerumXP.estimateXP(blockType: next.blockType, durationMinutes: durationMinutes)
            }

        } catch {
            print("ActiveFocusBarViewModel: Failed to load focus data - \(error)")
        }
    }

    public func startFocus() {
        guard let next = nextBlock else { return }

        activeBlock = next
        nextBlock = nil
        isInFocus = true
        focusStartTime = Date()
        startTimer()

        NotificationCenter.default.post(name: .focusSessionStarted, object: activeBlock)
    }

    public func pauseFocus() {
        isInFocus = false
        timerCancellable?.cancel()
        timerCancellable = nil

        NotificationCenter.default.post(name: .focusSessionPaused, object: activeBlock)
    }

    public func completeFocus() {
        guard let block = activeBlock else { return }

        isInFocus = false
        timerCancellable?.cancel()
        timerCancellable = nil

        // Calculate final XP
        let durationMinutes = Int(block.duration / 60)
        let xpEarned = PlannerumXP.estimateXP(blockType: block.blockType, durationMinutes: durationMinutes)

        // Post completion notification
        NotificationCenter.default.post(
            name: .focusSessionCompleted,
            object: block,
            userInfo: ["xpEarned": xpEarned]
        )

        // Clear state
        activeBlock = nil
        elapsedTime = nil

        // Reload to get next block
        Task {
            await loadActiveFocus()
        }
    }

    public func extendFocus(minutes: Int) {
        guard var block = activeBlock else { return }

        // Extend the block's end time
        block.endTime = block.endTime.addingTimeInterval(TimeInterval(minutes * 60))
        activeBlock = block

        // Recalculate XP
        let durationMinutes = Int(block.duration / 60)
        potentialXP = PlannerumXP.estimateXP(blockType: block.blockType, durationMinutes: durationMinutes)

        NotificationCenter.default.post(name: .focusSessionExtended, object: block)
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let startTime = self.focusStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let focusSessionStarted = Notification.Name("focusSessionStarted")
    static let focusSessionPaused = Notification.Name("focusSessionPaused")
    static let focusSessionCompleted = Notification.Name("focusSessionCompleted")
    static let focusSessionExtended = Notification.Name("focusSessionExtended")
}

// MARK: - Preview

#if DEBUG
struct ActiveFocusBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            ActiveFocusBar()
        }
        .background(PlannerumColors.voidPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
