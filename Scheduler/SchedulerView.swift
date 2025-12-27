// CosmoOS/Scheduler/SchedulerView.swift
// Main container view for the Cosmo Scheduler
//
// Design Philosophy:
// - Seamless mode switching between Plan and Today
// - Premium Apple-grade interactions at 120Hz
// - Floating context drawer for semantic exploration
// - Inline editor that respects user's visual focus

import SwiftUI

// MARK: - Scheduler View

/// The main scheduler container - orchestrates Plan Mode and Today Mode
public struct SchedulerView: View {

    // MARK: - State

    @StateObject private var engine: SchedulerEngine
    @State private var headerHeight: CGFloat = SchedulerDimensions.headerHeight
    @State private var showDatePicker: Bool = false
    @State private var animateIn: Bool = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Init

    init(database: CosmoDatabase? = nil) {
        _engine = StateObject(wrappedValue: SchedulerEngine(database: database))
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Background
                SchedulerColors.background
                    .ignoresSafeArea()

                // Main content stack
                VStack(spacing: 0) {
                    // Header bar
                    SchedulerHeader(
                        engine: engine,
                        showDatePicker: $showDatePicker
                    )
                    .frame(height: headerHeight)
                    .zIndex(10)

                    // Mode content
                    ZStack {
                        // Plan Mode (weekly grid)
                        if engine.mode == .plan {
                            PlanModeView(engine: engine)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .leading)),
                                    removal: .opacity.combined(with: .move(edge: .trailing))
                                ))
                        }

                        // Today Mode (action list)
                        if engine.mode == .today {
                            TodayModeView(engine: engine)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(SchedulerSprings.modeSwitch, value: engine.mode)
                }

                // Context drawer overlay (slides from right)
                if engine.isDrawerOpen, let selectedBlock = engine.selectedBlock {
                    ContextDrawerContainer(
                        engine: engine,
                        block: selectedBlock,
                        geometry: geometry
                    )
                    .zIndex(20)
                }

                // Inline editor overlay
                if let editorState = engine.editorState {
                    ScheduleBlockEditorOverlay(
                        engine: engine,
                        state: editorState,
                        geometry: geometry
                    )
                    .zIndex(30)
                }

                // Date picker popover
                if showDatePicker {
                    DatePickerOverlay(
                        selectedDate: Binding(
                            get: { engine.selectedDate },
                            set: { engine.goToDate($0) }
                        ),
                        isPresented: $showDatePicker
                    )
                    .zIndex(25)
                }

                // Loading indicator
                if engine.isLoading {
                    SchedulerLoadingIndicator()
                        .zIndex(40)
                }
            }
        }
        .onAppear {
            withAnimation(SchedulerSprings.gentle.delay(0.1)) {
                animateIn = true
            }
        }
        .environmentObject(engine)
    }
}

// MARK: - Scheduler Header

/// Premium header bar with date navigation and mode toggle
struct SchedulerHeader: View {

    @ObservedObject var engine: SchedulerEngine
    @Binding var showDatePicker: Bool
    @State private var isHoveringPrev: Bool = false
    @State private var isHoveringNext: Bool = false
    @State private var isHoveringToday: Bool = false
    @State private var isHoveringDateLabel: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Left section: Date navigation
            HStack(spacing: 12) {
                // Previous navigation
                NavigationButton(
                    systemImage: "chevron.left",
                    isHovered: $isHoveringPrev,
                    action: { engine.mode == .plan ? engine.previousWeek() : engine.previousDay() }
                )

                // Date display / picker trigger
                DateDisplayButton(
                    date: engine.selectedDate,
                    mode: engine.mode,
                    isHovered: $isHoveringDateLabel,
                    action: { showDatePicker.toggle() }
                )

                // Next navigation
                NavigationButton(
                    systemImage: "chevron.right",
                    isHovered: $isHoveringNext,
                    action: { engine.mode == .plan ? engine.nextWeek() : engine.nextDay() }
                )

                // Today button
                TodayButton(
                    isToday: Calendar.current.isDateInToday(engine.selectedDate),
                    isHovered: $isHoveringToday,
                    action: { engine.goToToday() }
                )
            }
            .padding(.leading, 20)

            Spacer()

            // Center: Mode toggle
            SchedulerModeToggle(
                mode: $engine.mode,
                onModeChange: { newMode in
                    engine.switchMode(to: newMode)
                }
            )

            Spacer()

            // Right section: Progress & actions
            HStack(spacing: 16) {
                // Progress indicator (Today mode only)
                if engine.mode == .today {
                    TodayProgressRing(
                        progress: engine.todayProgressPercentage,
                        completed: engine.todayProgress.completed,
                        total: engine.todayProgress.total
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                // Quick add button - opens popover near button
                QuickAddButton { anchorPoint in
                    engine.openEditor(
                        proposedStart: Date(),
                        anchorPoint: anchorPoint,
                        style: .popover
                    )
                }
            }
            .padding(.trailing, 20)
            .animation(SchedulerSprings.standard, value: engine.mode)
        }
        .frame(height: SchedulerDimensions.headerHeight)
        .background(
            SchedulerColors.headerBackground
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        )
    }
}

// MARK: - Navigation Button

private struct NavigationButton: View {
    let systemImage: String
    @Binding var isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(CosmoColors.textSecondary)
                .frame(width: SchedulerDimensions.smallButtonSize, height: SchedulerDimensions.smallButtonSize)
                .background(
                    Circle()
                        .fill(isHovered ? CosmoColors.glassGrey.opacity(0.5) : Color.clear)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
    }
}

// MARK: - Date Display Button

private struct DateDisplayButton: View {
    let date: Date
    let mode: SchedulerMode
    @Binding var isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(dateString)
                .font(CosmoTypography.titleSmall)
                .foregroundColor(CosmoColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? CosmoColors.glassGrey.opacity(0.3) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        if mode == .plan {
            // Show week range
            let calendar = Calendar.current
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!

            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: weekStart)
            let endStr = formatter.string(from: weekEnd)

            formatter.dateFormat = ", yyyy"
            let yearStr = formatter.string(from: weekEnd)

            return "\(startStr) – \(endStr)\(yearStr)"
        } else {
            // Show single day
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Today Button

private struct TodayButton: View {
    let isToday: Bool
    @Binding var isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Today")
                .font(CosmoTypography.label)
                .foregroundColor(isToday ? CosmoColors.textTertiary : CosmoColors.skyBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered && !isToday ? CosmoColors.skyBlue.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isToday ? Color.clear : CosmoColors.skyBlue.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isToday)
        .onHover { isHovered = $0 }
        .animation(SchedulerSprings.instant, value: isHovered)
        .animation(SchedulerSprings.standard, value: isToday)
    }
}

// MARK: - Mode Toggle

/// Premium pill-style mode toggle
struct SchedulerModeToggle: View {

    @Binding var mode: SchedulerMode
    let onModeChange: (SchedulerMode) -> Void

    @State private var hoverMode: SchedulerMode?
    @Namespace private var toggleNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SchedulerMode.allCases) { modeOption in
                ModeToggleOption(
                    modeOption: modeOption,
                    isSelected: mode == modeOption,
                    isHovered: hoverMode == modeOption,
                    namespace: toggleNamespace,
                    action: { onModeChange(modeOption) }
                )
                .onHover { hovering in
                    hoverMode = hovering ? modeOption : nil
                }
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(CosmoColors.glassGrey.opacity(0.3))
        )
        .animation(SchedulerSprings.snappy, value: mode)
    }
}

private struct ModeToggleOption: View {
    let modeOption: SchedulerMode
    let isSelected: Bool
    let isHovered: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: modeOption.systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(modeOption.displayName)
                    .font(CosmoTypography.label)
            }
            .foregroundColor(isSelected ? CosmoColors.textPrimary : CosmoColors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                            .matchedGeometryEffect(id: "modeBackground", in: namespace)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today Progress Ring

private struct TodayProgressRing: View {
    let progress: Double
    let completed: Int
    let total: Int

    @State private var animatedProgress: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            // Ring
            ZStack {
                Circle()
                    .stroke(CosmoColors.glassGrey.opacity(0.4), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        CosmoColors.emerald,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)

            // Count
            Text("\(completed)/\(total)")
                .font(CosmoTypography.labelSmall)
                .foregroundColor(CosmoColors.textSecondary)
        }
        .onAppear {
            withAnimation(SchedulerSprings.gentle.delay(0.2)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(SchedulerSprings.blockComplete) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Quick Add Button Position Preference

private struct QuickAddButtonPositionKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Quick Add Button

private struct QuickAddButton: View {
    let onTap: (CGPoint) -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        GeometryReader { geometry in
            Button {
                // Get button position in global coordinates
                let frame = geometry.frame(in: .global)
                let anchorPoint = CGPoint(
                    x: frame.maxX,  // Align to right edge
                    y: frame.maxY + 8  // Below the button
                )
                onTap(anchorPoint)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: SchedulerDimensions.mediumButtonSize, height: SchedulerDimensions.mediumButtonSize)
                    .background(
                        Circle()
                            .fill(CosmoColors.lavender)
                            .shadow(color: CosmoColors.lavender.opacity(0.3), radius: isHovered ? 8 : 4, x: 0, y: 2)
                    )
                    .scaleEffect(isHovered ? 1.08 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(SchedulerSprings.snappy, value: isHovered)
        }
        .frame(width: SchedulerDimensions.mediumButtonSize, height: SchedulerDimensions.mediumButtonSize)
    }
}

// MARK: - Context Drawer Container

private struct ContextDrawerContainer: View {
    @ObservedObject var engine: SchedulerEngine
    let block: ScheduleBlock
    let geometry: GeometryProxy

    var body: some View {
        HStack(spacing: 0) {
            // Dimming overlay (tap to dismiss)
            Color.black
                .opacity(0.1)
                .ignoresSafeArea()
                .onTapGesture {
                    engine.closeDrawer()
                }

            // Drawer content
            ContextDrawerView(engine: engine, block: block)
                .frame(width: SchedulerDimensions.drawerWidth)
                .background(
                    SchedulerColors.drawerBackground
                        .shadow(color: .black.opacity(0.12), radius: 20, x: -10, y: 0)
                )
                .transition(.drawerSlide)
        }
        .animation(SchedulerSprings.expand, value: engine.isDrawerOpen)
    }
}

// MARK: - Editor Overlay

private struct ScheduleBlockEditorOverlay: View {
    @ObservedObject var engine: SchedulerEngine
    let state: SchedulerEditorState
    let geometry: GeometryProxy

    var body: some View {
        ZStack {
            // Background dimming - only for modal style
            if !state.isPopover {
                Color.black
                    .opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        engine.closeEditor()
                    }
            } else {
                // Invisible tap catcher for popover dismiss
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        engine.closeEditor()
                    }
            }

            // Editor card
            ScheduleBlockEditor(engine: engine, state: state)
                .frame(width: state.isPopover ? 340 : SchedulerDimensions.editorCardWidth)
                .position(editorPosition)
                .transition(state.isPopover ? .popoverDrop : .editorPop)
        }
        .animation(SchedulerSprings.expand, value: state.mode)
    }

    private var editorPosition: CGPoint {
        if let anchor = state.anchorPoint {
            if state.isPopover {
                // Popover style: position below and aligned to right of anchor
                let editorWidth: CGFloat = 340
                let x = min(max(anchor.x - editorWidth / 2, editorWidth / 2 + 20),
                           geometry.size.width - editorWidth / 2 - 20)
                let y = min(anchor.y + 200,  // Offset down from anchor
                           geometry.size.height - 250)
                return CGPoint(x: x, y: y)
            } else {
                // Modal style: position near anchor, but keep on screen
                let x = min(max(anchor.x, SchedulerDimensions.editorCardWidth / 2 + 20),
                           geometry.size.width - SchedulerDimensions.editorCardWidth / 2 - 20)
                let y = min(max(anchor.y, SchedulerDimensions.editorCardMaxHeight / 2 + 80),
                           geometry.size.height - SchedulerDimensions.editorCardMaxHeight / 2 - 20)
                return CGPoint(x: x, y: y)
            }
        }
        // Center on screen
        return CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
}

// MARK: - Popover Drop Transition

extension AnyTransition {
    static var popoverDrop: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).combined(with: .offset(y: -8)),
            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).combined(with: .offset(y: -8))
        )
    }
}

// MARK: - Date Picker Overlay

private struct DatePickerOverlay: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Background dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isPresented = false
                }

            // Date picker
            VStack(spacing: 0) {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .frame(width: 320)
            .offset(y: -50)
            .transition(.editorPop)
        }
        .animation(SchedulerSprings.expand, value: isPresented)
    }
}

// MARK: - Loading Indicator

private struct SchedulerLoadingIndicator: View {
    @State private var isAnimating: Bool = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)

                    Text("Loading...")
                        .font(CosmoTypography.label)
                        .foregroundColor(CosmoColors.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                )
                .opacity(isAnimating ? 1 : 0)
                .offset(y: isAnimating ? 0 : 10)

                Spacer()
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(SchedulerSprings.standard.delay(0.2)) {
                isAnimating = true
            }
        }
    }
}

// Note: PlanModeView, TodayModeView, ContextDrawerView, and ScheduleBlockEditor
// are implemented in their respective files:
// - PlanMode/PlanModeView.swift
// - TodayMode/TodayModeView.swift
// - Shared/ContextDrawerView.swift
// - Shared/ScheduleBlockEditor.swift

// MARK: - Preview

#if DEBUG
struct SchedulerView_Previews: PreviewProvider {
    static var previews: some View {
        SchedulerView()
            .frame(width: 1200, height: 800)
    }
}
#endif
