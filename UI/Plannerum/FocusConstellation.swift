// CosmoOS/UI/Plannerum/FocusConstellation.swift
// Focus Constellation - Node-based HUD replacing the Active Focus Bar
// Matches Sanctuary's immersive "realm" aesthetic with constellation animations

import SwiftUI
import Combine

// MARK: - Focus Constellation

/// The Focus Constellation is a node-based HUD that replaces the flat Active Focus Bar.
/// It animates out from clicked tasks like a video game HUD, matching Sanctuary's feel.
///
/// Visual Layout (Active State):
/// ```
///                    ╭─────────╮
///               ╭────┤  ACTIVE ├────╮
///               │    ╰─────────╯    │
///          ╭────┴────╮         ╭────┴────╮
///          │  TIMER  │         │COMPLETE │
///          ╰────┬────╯         ╰────┬────╯
///               │                   │
///               ╰─────────┬─────────╯
///                    ╭────┴────╮
///                    │  SKIP   │
///                    ╰─────────╯
/// ```
public struct FocusConstellation: View {

    // MARK: - State

    @StateObject private var viewModel = FocusConstellationViewModel()

    // Animation states
    @State private var isExpanded = false
    @State private var nodesVisible: [Bool] = [false, false, false, false] // center, timer, complete, skip
    @State private var linesDrawn: [Bool] = [false, false, false] // timer-line, complete-line, skip-line
    @State private var infoPanelVisible = false
    @State private var pulsePhase: Double = 0
    @State private var hoveredNode: ConstellationNode?
    @State private var animationTimer: AnyCancellable?

    // MARK: - Layout Constants

    private enum Layout {
        static let nodeSize: CGFloat = 56
        static let iconSize: CGFloat = 24
        static let nodeSpacing: CGFloat = 80
        static let lineWidth: CGFloat = 2
        static let glowRadius: CGFloat = 16
        static let panelHeight: CGFloat = 180
        static let totalHeight: CGFloat = 280
    }

    // MARK: - Node Types

    private enum ConstellationNode: String, CaseIterable {
        case active
        case timer
        case complete
        case skip

        var icon: String {
            switch self {
            case .active: return "scope"
            case .timer: return "timer"
            case .complete: return "checkmark.circle.fill"
            case .skip: return "forward.fill"
            }
        }

        var label: String {
            switch self {
            case .active: return "ACTIVE"
            case .timer: return "TIMER"
            case .complete: return "COMPLETE"
            case .skip: return "SKIP"
            }
        }
    }

    // MARK: - Computed

    private var accentColor: Color {
        viewModel.activeBlock?.blockType.color ?? PlannerumColors.primary
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            if viewModel.activeBlock != nil || viewModel.isInFocus {
                // Active constellation
                activeConstellation
            } else {
                // Dormant state
                dormantConstellation
            }
        }
        .frame(height: Layout.totalHeight)
        .background(constellationBackground)
        .onAppear {
            Task {
                await viewModel.loadActiveFocus()
            }
            startPulseAnimation()
        }
        .onDisappear {
            animationTimer?.cancel()
        }
        .onChange(of: viewModel.activeBlock) { _, newBlock in
            if newBlock != nil {
                animateConstellationIn()
            } else {
                animateConstellationOut()
            }
        }
    }

    // MARK: - Background

    private var constellationBackground: some View {
        ZStack {
            // Base - subtle glass
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.04))
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial.opacity(0.2))
                )

            // Accent glow when active
            if viewModel.isInFocus {
                RadialGradient(
                    gradient: Gradient(colors: [
                        accentColor.opacity(0.08),
                        Color.clear
                    ]),
                    center: .top,
                    startRadius: 0,
                    endRadius: 200
                )
            }

            // Top border
            VStack {
                Rectangle()
                    .fill(
                        viewModel.isInFocus
                            ? accentColor.opacity(0.3)
                            : Color.white.opacity(0.08)
                    )
                    .frame(height: 1)
                Spacer()
            }
        }
    }

    // MARK: - Dormant Constellation

    private var dormantConstellation: some View {
        VStack(spacing: 24) {
            // Dormant message
            VStack(spacing: 8) {
                Text("Ready to focus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(PlannerumColors.textSecondary)

                Text("Tap a block to begin your session")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted)
            }

            // Dormant nodes (triangle formation)
            dormantNodes
        }
        .padding(.vertical, 32)
    }

    private var dormantNodes: some View {
        ZStack {
            // Connection lines (dashed, faint)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2 - 20)
                let left = CGPoint(x: size.width / 2 - 50, y: size.height / 2 + 30)
                let right = CGPoint(x: size.width / 2 + 50, y: size.height / 2 + 30)

                let linePath = Path { path in
                    path.move(to: center)
                    path.addLine(to: left)
                    path.move(to: center)
                    path.addLine(to: right)
                    path.move(to: left)
                    path.addLine(to: right)
                }

                context.stroke(
                    linePath,
                    with: .color(Color.white.opacity(0.06)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
            .frame(width: 200, height: 100)

            // Dormant node dots
            VStack(spacing: 0) {
                // Top node
                dormantNodeDot
                    .offset(y: -20)

                HStack(spacing: 80) {
                    dormantNodeDot
                    dormantNodeDot
                }
                .offset(y: 10)
            }
        }
        .frame(height: 80)
    }

    private var dormantNodeDot: some View {
        Circle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
    }

    // MARK: - Active Constellation

    private var activeConstellation: some View {
        VStack(spacing: 0) {
            // Nodes area
            ZStack {
                // Connection lines
                connectionLines

                // Nodes
                constellationNodes
            }
            .frame(height: 140)

            // Info panel
            if let block = viewModel.activeBlock {
                infoPanel(for: block)
                    .opacity(infoPanelVisible ? 1 : 0)
                    .offset(y: infoPanelVisible ? 0 : 20)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Connection Lines

    private var connectionLines: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            let centerY: CGFloat = 30

            let activePos = CGPoint(x: centerX, y: centerY)
            let timerPos = CGPoint(x: centerX - Layout.nodeSpacing, y: centerY + 50)
            let completePos = CGPoint(x: centerX + Layout.nodeSpacing, y: centerY + 50)
            let skipPos = CGPoint(x: centerX, y: centerY + 100)

            // Draw lines with animated dash
            let dashPhase = pulsePhase * 5

            // Active -> Timer line
            if linesDrawn[0] {
                var path = Path()
                path.move(to: activePos)
                path.addLine(to: timerPos)
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.15)),
                    style: StrokeStyle(lineWidth: Layout.lineWidth, dash: [6, 4], dashPhase: dashPhase)
                )
            }

            // Active -> Complete line
            if linesDrawn[1] {
                var path = Path()
                path.move(to: activePos)
                path.addLine(to: completePos)
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.15)),
                    style: StrokeStyle(lineWidth: Layout.lineWidth, dash: [6, 4], dashPhase: dashPhase)
                )
            }

            // Active -> Skip line (through center)
            if linesDrawn[2] {
                var path = Path()
                path.move(to: activePos)
                path.addLine(to: skipPos)
                context.stroke(
                    path,
                    with: .color(Color.white.opacity(0.15)),
                    style: StrokeStyle(lineWidth: Layout.lineWidth, dash: [6, 4], dashPhase: dashPhase)
                )
            }
        }
    }

    // MARK: - Constellation Nodes

    private var constellationNodes: some View {
        ZStack {
            // Center: Active node
            constellationNode(.active, index: 0)
                .offset(y: -40)

            // Left: Timer node
            constellationNode(.timer, index: 1)
                .offset(x: -Layout.nodeSpacing, y: 10)

            // Right: Complete node
            constellationNode(.complete, index: 2)
                .offset(x: Layout.nodeSpacing, y: 10)

            // Bottom: Skip node
            constellationNode(.skip, index: 3)
                .offset(y: 60)
        }
    }

    private func constellationNode(_ node: ConstellationNode, index: Int) -> some View {
        let isVisible = index < nodesVisible.count && nodesVisible[index]
        let isHovered = hoveredNode == node
        let isPulsing = node == .active && viewModel.isInFocus

        return Button(action: { handleNodeTap(node) }) {
            ZStack {
                // Glow (on hover or active pulse)
                if isHovered || isPulsing {
                    Circle()
                        .fill(accentColor.opacity(isPulsing ? 0.2 + 0.1 * sin(pulsePhase) : 0.3))
                        .frame(width: Layout.nodeSize + Layout.glowRadius, height: Layout.nodeSize + Layout.glowRadius)
                        .blur(radius: Layout.glowRadius / 2)
                }

                // Node background
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0.08))
                    .frame(width: Layout.nodeSize, height: Layout.nodeSize)

                // Node border
                Circle()
                    .strokeBorder(
                        isHovered ? accentColor.opacity(0.5) : Color.white.opacity(0.20),
                        lineWidth: 2
                    )
                    .frame(width: Layout.nodeSize, height: Layout.nodeSize)

                // Icon
                VStack(spacing: 4) {
                    Image(systemName: node.icon)
                        .font(.system(size: Layout.iconSize, weight: .medium))
                        .foregroundColor(
                            node == .active
                                ? accentColor
                                : (isHovered ? PlannerumColors.textPrimary : PlannerumColors.textSecondary)
                        )

                    if node == .timer && viewModel.isInFocus {
                        // Show timer value
                        Text(formatTime(viewModel.elapsedTime ?? 0))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(PlannerumColors.textMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(PlannerumSprings.hover) {
                hoveredNode = hovering ? node : nil
            }
        }
        .scaleEffect(isVisible ? 1.0 : 0.3)
        .opacity(isVisible ? 1.0 : 0)
        .animation(PlannerumSprings.expand.delay(Double(index) * 0.08), value: isVisible)
    }

    // MARK: - Info Panel

    private func infoPanel(for block: ScheduleBlockViewModel) -> some View {
        VStack(spacing: 12) {
            // Separator
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 40)

            // Block info
            VStack(spacing: 8) {
                // Type + Title
                HStack(spacing: 8) {
                    Image(systemName: block.blockType.icon)
                        .font(.system(size: 14))
                        .foregroundColor(accentColor)

                    Text("\(block.blockType.displayName.uppercased()): \(block.title)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PlannerumColors.textPrimary)
                        .lineLimit(1)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 6)

                        // Fill
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * viewModel.progress, height: 6)
                            .shadow(color: accentColor.opacity(0.5), radius: 4, x: 0, y: 0)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)

                // Time + XP
                HStack(spacing: 16) {
                    // Remaining time
                    Text(formatTimeRemaining(block))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(PlannerumColors.textSecondary)

                    Text("·")
                        .foregroundColor(PlannerumColors.textMuted)

                    // XP projection
                    HStack(spacing: 4) {
                        Text("+\(viewModel.potentialXP)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                        Text("XP projected")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(PlannerumColors.xpGold)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatTimeRemaining(_ block: ScheduleBlockViewModel) -> String {
        let remaining = block.endTime.timeIntervalSince(Date())
        if remaining <= 0 { return "0:00 remaining" }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d remaining", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d remaining", minutes, seconds)
        }
    }

    // MARK: - Node Actions

    private func handleNodeTap(_ node: ConstellationNode) {
        switch node {
        case .active:
            // Toggle timer display mode
            break

        case .timer:
            // Toggle elapsed/remaining
            viewModel.toggleTimerMode()

        case .complete:
            // Complete the block
            withAnimation(PlannerumSprings.expand) {
                viewModel.completeFocus()
            }
            // TODO: Trigger XP tracer animation

        case .skip:
            // Skip to next block
            withAnimation(PlannerumSprings.expand) {
                viewModel.skipBlock()
            }
        }
    }

    // MARK: - Animations

    private func animateConstellationIn() {
        // Reset states
        nodesVisible = [false, false, false, false]
        linesDrawn = [false, false, false]
        infoPanelVisible = false

        // 1. Nodes fly out (staggered 0.08s each)
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
                withAnimation(PlannerumSprings.expand) {
                    nodesVisible[i] = true
                }
            }
        }

        // 2. Lines draw in (0.2s each, after nodes)
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 + Double(i) * 0.1) {
                withAnimation(.easeOut(duration: 0.2)) {
                    linesDrawn[i] = true
                }
            }
        }

        // 3. Info panel fades up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.3)) {
                infoPanelVisible = true
            }
        }

        isExpanded = true
    }

    private func animateConstellationOut() {
        withAnimation(PlannerumSprings.expand) {
            infoPanelVisible = false
            linesDrawn = [false, false, false]
            nodesVisible = [false, false, false, false]
        }
        isExpanded = false
    }

    private func startPulseAnimation() {
        animationTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                pulsePhase += 0.08
            }
    }
}

// MARK: - Focus Constellation View Model

@MainActor
public class FocusConstellationViewModel: ObservableObject {

    @Published public var activeBlock: ScheduleBlockViewModel?
    @Published public var nextBlock: ScheduleBlockViewModel?
    @Published public var isInFocus = false
    @Published public var elapsedTime: TimeInterval?
    @Published public var potentialXP: Int = 0
    @Published public var showElapsed = true // vs remaining

    private var timerCancellable: AnyCancellable?
    private var focusStartTime: Date?

    public var progress: Double {
        guard let block = activeBlock else { return 0 }
        let total = block.endTime.timeIntervalSince(block.startTime)
        let elapsed = Date().timeIntervalSince(block.startTime)
        return min(max(elapsed / total, 0), 1)
    }

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
                    isCompleted: metadata.isCompleted ?? false
                )
            }
            .sorted { $0.startTime < $1.startTime }

            // Find active block
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
            print("FocusConstellationViewModel: Failed to load focus data - \(error)")
        }
    }

    public func toggleTimerMode() {
        showElapsed.toggle()
    }

    public func completeFocus() {
        guard let block = activeBlock else { return }

        isInFocus = false
        timerCancellable?.cancel()
        timerCancellable = nil

        let durationMinutes = Int(block.duration / 60)
        let xpEarned = PlannerumXP.estimateXP(blockType: block.blockType, durationMinutes: durationMinutes)

        NotificationCenter.default.post(
            name: .focusSessionCompleted,
            object: block,
            userInfo: ["xpEarned": xpEarned]
        )

        activeBlock = nil
        elapsedTime = nil

        Task {
            await loadActiveFocus()
        }
    }

    public func skipBlock() {
        guard activeBlock != nil else { return }

        isInFocus = false
        timerCancellable?.cancel()
        timerCancellable = nil

        NotificationCenter.default.post(name: .focusSessionSkipped, object: activeBlock)

        activeBlock = nil
        elapsedTime = nil

        Task {
            await loadActiveFocus()
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

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let startTime = self.focusStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
    }
}

// MARK: - Additional Notification

extension Notification.Name {
    static let focusSessionSkipped = Notification.Name("focusSessionSkipped")
}

// MARK: - Preview

#if DEBUG
struct FocusConstellation_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            FocusConstellation()
        }
        .background(PlannerumColors.voidPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - HORIZONTAL FOCUS STRIP
// ═══════════════════════════════════════════════════════════════════════════════

/// A compact horizontal focus strip that spans full width at the bottom.
/// Replaces the tall FocusConstellation to reduce dead space.
///
/// Layout: [Status Text] ─────── [Nodes inline] ─────── [Progress/XP]
public struct HorizontalFocusStrip: View {

    @StateObject private var viewModel = FocusConstellationViewModel()
    @State private var pulsePhase: Double = 0
    @State private var animationTimer: AnyCancellable?

    private var accentColor: Color {
        viewModel.activeBlock?.blockType.color ?? PlannerumColors.nowMarker
    }

    public var body: some View {
        Group {
            if let block = viewModel.activeBlock, viewModel.isInFocus {
                // Active state - inline layout (only shown when a session is active)
                HStack(spacing: 0) {
                    activeFocusContent(block: block)
                }
                .frame(height: 56)
                .background(stripBackground)
            }
            // Dormant state removed — no bar when no session is active
        }
        .onAppear {
            Task { await viewModel.loadActiveFocus() }
            startPulse()
        }
        .onDisappear {
            animationTimer?.cancel()
        }
    }

    // MARK: - Active Content

    private func activeFocusContent(block: ScheduleBlockViewModel) -> some View {
        HStack(spacing: 16) {
            // Left: Block info
            HStack(spacing: 10) {
                // Pulsing indicator
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: accentColor.opacity(0.6), radius: 4 + sin(pulsePhase) * 2)
                    .scaleEffect(1.0 + 0.15 * sin(pulsePhase))

                // Block type + title
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.blockType.displayName.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(accentColor)
                        .tracking(1)

                    Text(block.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(PlannerumColors.textPrimary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 200, alignment: .leading)

            Spacer()

            // Center: Progress bar
            progressBar(for: block)
                .frame(maxWidth: 300)

            Spacer()

            // Right: Actions + XP
            HStack(spacing: 12) {
                // Timer
                Text(formatElapsed(viewModel.elapsedTime ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(PlannerumColors.textSecondary)

                // XP
                HStack(spacing: 4) {
                    Text("+\(viewModel.potentialXP)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor)
                    Text("XP")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PlannerumColors.textMuted)
                }

                // Action buttons inline
                HStack(spacing: 8) {
                    actionButton(icon: "checkmark.circle.fill", color: .green) {
                        viewModel.completeFocus()
                    }
                    actionButton(icon: "forward.fill", color: PlannerumColors.textMuted) {
                        viewModel.skipBlock()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Dormant Content

    private var dormantContent: some View {
        HStack(spacing: 16) {
            // Left: Status
            HStack(spacing: 10) {
                // Calm indicator
                Circle()
                    .fill(PlannerumColors.textMuted.opacity(0.3))
                    .frame(width: 8, height: 8)

                Text("Ready to focus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PlannerumColors.textMuted)

                Text("·")
                    .foregroundColor(PlannerumColors.textMuted.opacity(0.5))

                Text("Tap a block to begin")
                    .font(.system(size: 12))
                    .foregroundColor(PlannerumColors.textMuted.opacity(0.7))
            }

            Spacer()

            // Right: Dormant nodes (smaller)
            HStack(spacing: 12) {
                dormantNode
                dormantNode
                dormantNode
            }
        }
        .padding(.horizontal, 20)
    }

    private var dormantNode: some View {
        Circle()
            .fill(Color.white.opacity(0.04))
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .frame(width: 28, height: 28)
    }

    // MARK: - Progress Bar

    private func progressBar(for block: ScheduleBlockViewModel) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 4)

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * viewModel.progress, height: 4)
                    .shadow(color: accentColor.opacity(0.4), radius: 3)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Action Button

    private func actionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Background

    private var stripBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        viewModel.isInFocus
                            ? accentColor.opacity(0.2)
                            : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Helpers

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startPulse() {
        animationTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                pulsePhase += 0.1
            }
    }
}
