// CosmoOS/UI/FocusMode/Research/TranscriptSpineView.swift
// Vertical transcript backbone with branching annotations
// Notes branch right, Questions branch left, Insights branch right
// December 2025 - Research Focus Mode transcript visualization

import SwiftUI

// MARK: - Transcript Spine View

/// The vertical transcript backbone for Research Focus Mode.
/// Displays transcript sections with annotations branching off left and right.
struct TranscriptSpineView: View {
    // MARK: - Properties

    /// All transcript sections
    let sections: [TranscriptSection]

    /// Currently playing timestamp (for highlighting)
    let currentTimestamp: TimeInterval

    /// Callback when section is tapped (seek to timestamp)
    let onSectionTap: (TranscriptSection) -> Void

    /// Callback to add annotation
    let onAddAnnotation: (TranscriptSection, AnnotationType) -> Void

    /// Callback when annotation is tapped
    let onAnnotationTap: (ResearchAnnotation) -> Void

    /// Callback when annotation is edited
    let onAnnotationEdit: (ResearchAnnotation) -> Void

    /// Callback when annotation is deleted
    let onAnnotationDelete: (ResearchAnnotation) -> Void

    // MARK: - State

    @State private var hoveredSectionID: UUID?
    @State private var expandedAnnotationID: UUID?

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections) { section in
                        TranscriptSectionRow(
                            section: section,
                            isPlaying: isPlaying(section),
                            isHovered: hoveredSectionID == section.id,
                            expandedAnnotationID: $expandedAnnotationID,
                            onTap: { onSectionTap(section) },
                            onAddAnnotation: { type in onAddAnnotation(section, type) },
                            onAnnotationTap: onAnnotationTap,
                            onAnnotationEdit: onAnnotationEdit,
                            onAnnotationDelete: onAnnotationDelete
                        )
                        .id(section.id)
                        .onHover { hovering in
                            hoveredSectionID = hovering ? section.id : nil
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .onChange(of: currentTimestamp) { _, newTime in
                // Auto-scroll to current section
                if let currentSection = sections.first(where: {
                    newTime >= $0.startTime && newTime < $0.endTime
                }) {
                    withAnimation(ProMotionSprings.gentle) {
                        proxy.scrollTo(currentSection.id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func isPlaying(_ section: TranscriptSection) -> Bool {
        currentTimestamp >= section.startTime && currentTimestamp < section.endTime
    }
}

// MARK: - Transcript Section Row

/// A single section in the transcript spine with annotations
struct TranscriptSectionRow: View {
    let section: TranscriptSection
    let isPlaying: Bool
    let isHovered: Bool
    @Binding var expandedAnnotationID: UUID?

    let onTap: () -> Void
    let onAddAnnotation: (AnnotationType) -> Void
    let onAnnotationTap: (ResearchAnnotation) -> Void
    let onAnnotationEdit: (ResearchAnnotation) -> Void
    let onAnnotationDelete: (ResearchAnnotation) -> Void

    @State private var showAnnotationMenu = false

    // Separate annotations by branch direction
    private var leftAnnotations: [ResearchAnnotation] {
        section.annotations.filter { $0.type.branchDirection == .left }
    }

    private var rightAnnotations: [ResearchAnnotation] {
        section.annotations.filter { $0.type.branchDirection == .right }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // LEFT ANNOTATIONS (Questions)
            annotationColumn(annotations: leftAnnotations, side: .left)
                .frame(width: 200)

            // CENTER SPINE
            VStack(alignment: .leading, spacing: 0) {
                // Spine connector line
                Rectangle()
                    .fill(spineColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        // Timestamp badge
                        timestampBadge
                    }
            }
            .frame(width: 60)
            .overlay(alignment: .trailing) {
                // Transcript text
                transcriptContent
                    .offset(x: 20)
            }

            // RIGHT ANNOTATIONS (Notes, Insights)
            annotationColumn(annotations: rightAnnotations, side: .right)
                .frame(width: 200)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    // MARK: - Timestamp Badge

    private var timestampBadge: some View {
        HStack(spacing: 4) {
            if isPlaying {
                Circle()
                    .fill(CosmoColors.blockResearch)
                    .frame(width: 6, height: 6)
            }

            Text(section.startTimeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isPlaying ? CosmoColors.blockResearch : Color.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isPlaying ? CosmoColors.blockResearch.opacity(0.15) : Color.white.opacity(0.05))
        )
    }

    // MARK: - Transcript Content

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Speaker name if available
            if let speaker = section.speakerName {
                Text(speaker)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CosmoColors.blockResearch)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            // Transcript text
            Text(section.text)
                .font(.system(size: 13))
                .foregroundColor(isPlaying ? .white : Color.white.opacity(0.7))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // Add annotation button (on hover)
            if isHovered {
                addAnnotationButtons
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 280, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isPlaying ? Color.white.opacity(0.08) : Color.clear)
        )
        .animation(ProMotionSprings.hover, value: isPlaying)
        .animation(ProMotionSprings.hover, value: isHovered)
    }

    // MARK: - Add Annotation Buttons

    private var addAnnotationButtons: some View {
        HStack(spacing: 8) {
            ForEach(AnnotationType.allCases, id: \.rawValue) { type in
                Button {
                    onAddAnnotation(type)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: type.icon)
                            .font(.system(size: 10))
                        Text(type.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(type.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(type.color.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Annotation Column

    @ViewBuilder
    private func annotationColumn(annotations: [ResearchAnnotation], side: BranchDirection) -> some View {
        VStack(alignment: side == .left ? .trailing : .leading, spacing: 12) {
            ForEach(annotations) { annotation in
                AnnotationBranchView(
                    annotation: annotation,
                    side: side,
                    isExpanded: expandedAnnotationID == annotation.id,
                    onTap: {
                        withAnimation(ProMotionSprings.snappy) {
                            if expandedAnnotationID == annotation.id {
                                expandedAnnotationID = nil
                            } else {
                                expandedAnnotationID = annotation.id
                            }
                        }
                        onAnnotationTap(annotation)
                    },
                    onEdit: { onAnnotationEdit(annotation) },
                    onDelete: { onAnnotationDelete(annotation) }
                )
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private var spineColor: Color {
        isPlaying ? CosmoColors.blockResearch : Color.white.opacity(0.15)
    }
}

// MARK: - Annotation Branch View

/// An annotation that branches off from the transcript spine
struct AnnotationBranchView: View {
    let annotation: ResearchAnnotation
    let side: BranchDirection
    let isExpanded: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var accentColor: Color {
        annotation.type.color
    }

    var body: some View {
        HStack(spacing: 0) {
            // Branch connector (on appropriate side)
            if side == .left {
                annotationCard
                branchConnector
            } else {
                branchConnector
                annotationCard
            }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Branch Connector

    private var branchConnector: some View {
        BezierBranchPath(side: side)
            .stroke(
                accentColor.opacity(isHovered ? 0.6 : 0.3),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: 30, height: 40)
    }

    // MARK: - Annotation Card

    private var annotationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: annotation.type.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accentColor)

                Text(annotation.type.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(accentColor)
                    .tracking(0.5)

                Spacer()

                Text(annotation.timestampString)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.4))
            }

            // Content
            Text(annotation.content)
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.85))
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            // Actions (expanded)
            if isExpanded {
                HStack(spacing: 12) {
                    Button(action: onEdit) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                            Text("Edit")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Delete")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(Color.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Linked atoms count
                    if !annotation.linkedAtomUUIDs.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                            Text("\(annotation.linkedAtomUUIDs.count)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(Color.white.opacity(0.4))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(10)
        .frame(width: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#1A1A25"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isHovered ? accentColor.opacity(0.5) : accentColor.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
        .shadow(
            color: isHovered ? accentColor.opacity(0.2) : Color.black.opacity(0.2),
            radius: isHovered ? 8 : 4
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Bezier Branch Path

/// Curved connector path for annotation branches
struct BezierBranchPath: Shape {
    let side: BranchDirection

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let startX = side == .left ? rect.maxX : rect.minX
        let endX = side == .left ? rect.minX : rect.maxX
        let midY = rect.midY

        path.move(to: CGPoint(x: startX, y: midY))

        // Bezier curve control points
        let controlPoint1 = CGPoint(
            x: side == .left ? startX - rect.width * 0.5 : startX + rect.width * 0.5,
            y: midY
        )
        let controlPoint2 = CGPoint(
            x: side == .left ? endX + rect.width * 0.3 : endX - rect.width * 0.3,
            y: midY
        )

        path.addCurve(
            to: CGPoint(x: endX, y: midY),
            control1: controlPoint1,
            control2: controlPoint2
        )

        return path
    }
}

// MARK: - Preview

#if DEBUG
struct TranscriptSpineView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            TranscriptSpineView(
                sections: [
                    TranscriptSection(
                        startTime: 0,
                        endTime: 30,
                        text: "Welcome back to another episode. Today we're going to talk about how to completely reinvent your life in 6-12 months.",
                        speakerName: "Dan Koe",
                        annotations: [
                            ResearchAnnotation(
                                type: .note,
                                content: "Key theme: transformation through subtraction",
                                timestamp: 15
                            )
                        ]
                    ),
                    TranscriptSection(
                        startTime: 30,
                        endTime: 65,
                        text: "The first thing you need to understand is that identity is not fixed. It's a story you tell yourself. And that story can be rewritten.",
                        speakerName: "Dan Koe",
                        annotations: [
                            ResearchAnnotation(
                                type: .insight,
                                content: "Identity as narrative - can be rewritten",
                                timestamp: 45
                            ),
                            ResearchAnnotation(
                                type: .question,
                                content: "How does this relate to fixed vs growth mindset?",
                                timestamp: 50
                            )
                        ]
                    ),
                    TranscriptSection(
                        startTime: 65,
                        endTime: 100,
                        text: "Most people try to add more to their life when they want to change. More habits, more goals, more things. But real transformation comes from subtraction.",
                        speakerName: "Dan Koe",
                        annotations: []
                    )
                ],
                currentTimestamp: 40,
                onSectionTap: { section in print("Tap: \(section.startTimeString)") },
                onAddAnnotation: { section, type in print("Add \(type) to \(section.startTimeString)") },
                onAnnotationTap: { annotation in print("Annotation: \(annotation.content)") },
                onAnnotationEdit: { annotation in print("Edit: \(annotation.content)") },
                onAnnotationDelete: { annotation in print("Delete: \(annotation.content)") }
            )
            .frame(width: 700, height: 600)
        }
    }
}
#endif
