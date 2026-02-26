// CosmoOS/UI/FocusMode/Research/TranscriptSpineView.swift
// Vertical transcript backbone with branching annotations
// Notes branch right, Questions branch left, Insights branch right
// December 2025 - Research Focus Mode transcript visualization

import SwiftUI

// MARK: - Annotation Geometry Preference Keys

/// Reports anchor points in transcript space for each annotation.
private struct AnnotationAnchorPointKey: PreferenceKey {
    static var defaultValue: [UUID: CGPoint] = [:]
    static func reduce(value: inout [UUID: CGPoint], nextValue: () -> [UUID: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Reports annotation card centers in transcript-space coordinates.
private struct AnnotationCardCenterPointKey: PreferenceKey {
    static var defaultValue: [UUID: CGPoint] = [:]
    static func reduce(value: inout [UUID: CGPoint], nextValue: () -> [UUID: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

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

    /// Callback when annotation is edited (annotation, newContent)
    let onAnnotationEdit: (ResearchAnnotation, String) -> Void

    /// Callback when annotation is deleted
    let onAnnotationDelete: (ResearchAnnotation) -> Void

    /// Callback when annotation is dragged to a new position
    let onAnnotationPositionChange: (ResearchAnnotation, CGPoint) -> Void

    /// Callback to create a highlight annotation from selected text
    let onCreateHighlightAnnotation: (UUID, AnnotationType, String, NSRange) -> Void

    // MARK: - State

    @State private var hoveredSectionID: UUID?
    @State private var expandedAnnotationID: UUID?
    @State private var annotationAnchorPoints: [UUID: CGPoint] = [:]
    @State private var annotationCardCenters: [UUID: CGPoint] = [:]

    private var allAnnotations: [ResearchAnnotation] {
        sections.flatMap(\.annotations)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            transcriptHeader

            // Scrollable transcript content
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(sections) { section in
                            TranscriptSectionRow(
                                section: section,
                                isPlaying: isPlaying(section),
                                isHovered: hoveredSectionID == section.id,
                                onTap: { onSectionTap(section) },
                                onAddAnnotation: { type in onAddAnnotation(section, type) },
                                onCreateHighlightAnnotation: onCreateHighlightAnnotation
                            )
                            .id(section.id)
                            .onHover { hovering in
                                hoveredSectionID = hovering ? section.id : nil
                            }
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
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
        .coordinateSpace(name: "transcriptSpineRoot")
        .overlay {
            if !allAnnotations.isEmpty {
                annotationCanvasLayer
            }
        }
        .onPreferenceChange(AnnotationAnchorPointKey.self) { points in
            annotationAnchorPoints = points
        }
        .onPreferenceChange(AnnotationCardCenterPointKey.self) { points in
            annotationCardCenters = points
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.borderActive.opacity(0.8), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(0.3),
            radius: 12,
            y: 4
        )
    }

    // MARK: - Transcript Header

    private var transcriptHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12, weight: .medium))
                Text("TRANSCRIPT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
            }
            .foregroundColor(CosmoColors.blockResearch)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CosmoColors.blockResearch.opacity(0.15), in: Capsule())

            Spacer()

            Text("\(sections.count) sections")
                .font(.system(size: 11))
                .foregroundColor(DS.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DS.borderSubtle)
    }

    // MARK: - Helpers

    private func isPlaying(_ section: TranscriptSection) -> Bool {
        currentTimestamp >= section.startTime && currentTimestamp < section.endTime
    }

    private var annotationCanvasLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(allAnnotations) { annotation in
                if annotation.hasCustomPosition {
                    AnnotationConnectionLine(
                        from: anchorPoint(for: annotation),
                        to: cardCenter(for: annotation),
                        color: annotation.type.color
                    )
                }
            }
            .allowsHitTesting(false)

            ForEach(allAnnotations) { annotation in
                let anchor = anchorPoint(for: annotation)
                let defaultCenter = CGPoint(x: anchor.x + 180, y: anchor.y)

                AnnotationCardView(
                    annotation: annotation,
                    isExpanded: expandedAnnotationID == annotation.id,
                    onTap: {
                        withAnimation(ProMotionSprings.snappy) {
                            expandedAnnotationID = expandedAnnotationID == annotation.id ? nil : annotation.id
                        }
                        onAnnotationTap(annotation)
                    },
                    onEdit: { newContent in
                        onAnnotationEdit(annotation, newContent)
                    },
                    onDelete: {
                        onAnnotationDelete(annotation)
                    },
                    onPositionChange: { newOffset in
                        onAnnotationPositionChange(annotation, newOffset)
                    }
                )
                .position(defaultCenter)
                .background(
                    GeometryReader { geo in
                        let frame = geo.frame(in: .named("transcriptSpineRoot"))
                        Color.clear.preference(
                            key: AnnotationCardCenterPointKey.self,
                            value: [annotation.id: CGPoint(x: frame.midX, y: frame.midY)]
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func anchorPoint(for annotation: ResearchAnnotation) -> CGPoint {
        if let anchor = annotationAnchorPoints[annotation.id] {
            return anchor
        }

        let index = allAnnotations.firstIndex(where: { $0.id == annotation.id }) ?? 0
        return CGPoint(x: 420, y: 100 + CGFloat(index * 72))
    }

    private func cardCenter(for annotation: ResearchAnnotation) -> CGPoint {
        if let cardCenter = annotationCardCenters[annotation.id] {
            return cardCenter
        }

        let anchor = anchorPoint(for: annotation)
        let offset = annotation.customOffset ?? .zero
        return CGPoint(x: anchor.x + 180 + offset.x, y: anchor.y + offset.y)
    }
}

// MARK: - Transcript Section Row

/// A single section in the transcript spine with annotations
struct TranscriptSectionRow: View {
    let section: TranscriptSection
    let isPlaying: Bool
    let isHovered: Bool

    let onTap: () -> Void
    let onAddAnnotation: (AnnotationType) -> Void
    let onCreateHighlightAnnotation: (UUID, AnnotationType, String, NSRange) -> Void

    @State private var selectedTextInfo: (String, NSRange)? = nil
    @State private var showAnnotationPopover = false

    private var allAnnotations: [ResearchAnnotation] {
        section.annotations
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Spine line with timestamp
            VStack(spacing: 0) {
                timestampBadge

                Rectangle()
                    .fill(spineColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 50)

            transcriptContent
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
                .foregroundColor(isPlaying ? CosmoColors.blockResearch : DS.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isPlaying ? CosmoColors.blockResearch.opacity(0.15) : DS.border)
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

            // Transcript text (selectable with highlight support)
            SelectableTranscriptText(
                text: section.text,
                highlights: section.highlights,
                isPlaying: isPlaying,
                onTextSelected: { selectedText, range in
                    selectedTextInfo = (selectedText, range)
                    showAnnotationPopover = true
                }
            )
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .background(
                GeometryReader { textGeo in
                    Color.clear.preference(
                        key: AnnotationAnchorPointKey.self,
                        value: annotationAnchorPoints(in: textGeo.frame(in: .named("transcriptSpineRoot")))
                    )
                }
            )

            // Add annotation button (on hover)
            if isHovered {
                addAnnotationButtons
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .layoutPriority(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isPlaying ? DS.border : Color.clear)
        )
        .animation(ProMotionSprings.hover, value: isPlaying)
        .animation(ProMotionSprings.hover, value: isHovered)
        .popover(isPresented: $showAnnotationPopover) {
            AnnotationTypePickerPopover(
                selectedText: selectedTextInfo?.0 ?? "",
                onSelect: { type in
                    if let info = selectedTextInfo {
                        onCreateHighlightAnnotation(section.id, type, info.0, info.1)
                    }
                    showAnnotationPopover = false
                    selectedTextInfo = nil
                },
                onCancel: {
                    showAnnotationPopover = false
                    selectedTextInfo = nil
                }
            )
        }
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

    // MARK: - Helpers

    private func annotationAnchorPoints(in textFrame: CGRect) -> [UUID: CGPoint] {
        var points: [UUID: CGPoint] = [:]
        for annotation in allAnnotations {
            points[annotation.id] = anchorPoint(for: annotation, in: textFrame)
        }
        return points
    }

    private func anchorPoint(for annotation: ResearchAnnotation, in textFrame: CGRect) -> CGPoint {
        let anchorX = textFrame.maxX - 8
        guard let highlight = section.highlights.first(where: { $0.annotationID == annotation.id }) else {
            return CGPoint(x: anchorX, y: textFrame.midY)
        }

        let textLength = max(1, (section.text as NSString).length)
        let progress = min(1, max(0, CGFloat(highlight.startCharIndex) / CGFloat(textLength)))
        let anchorY = textFrame.minY + (progress * max(textFrame.height, 1))
        return CGPoint(x: anchorX, y: anchorY)
    }

    private var spineColor: Color {
        isPlaying ? CosmoColors.blockResearch : DS.borderActive
    }
}

// MARK: - Annotation Card View

/// Compact annotation card (all annotations on right side, differentiated by color)
/// Supports double-click to edit inline, click outside to save
struct AnnotationCardView: View {
    let annotation: ResearchAnnotation
    let isExpanded: Bool
    let onTap: () -> Void
    let onEdit: (String) -> Void
    let onDelete: () -> Void
    let onPositionChange: (CGPoint) -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editContent: String = ""
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @FocusState private var isTextFieldFocused: Bool

    private var accentColor: Color {
        annotation.type.color
    }

    var body: some View {
        HStack(spacing: 8) {
            // Color indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                // Type badge
                HStack(spacing: 4) {
                    Image(systemName: annotation.type.icon)
                        .font(.system(size: 9, weight: .semibold))
                    Text(annotation.type.label.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundColor(accentColor)

                // Content — editable or static
                if isEditing {
                    ZStack(alignment: .topLeading) {
                        if editContent.isEmpty {
                            Text("Add a note...")
                                .font(.system(size: 11))
                                .foregroundColor(DS.textMuted)
                                .padding(.top, 4)
                                .padding(.leading, 2)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $editContent)
                            .font(.system(size: 11))
                            .foregroundColor(DS.text)
                            .scrollContentBackground(.hidden)
                            .focused($isTextFieldFocused)
                            .frame(minHeight: 40, maxHeight: 120)
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DS.border)
                    )
                } else {
                    if !annotation.content.isEmpty {
                        Text(annotation.content)
                            .font(.system(size: 11))
                            .foregroundColor(DS.text)
                            .lineLimit(isExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Double-click to edit")
                            .font(.system(size: 11))
                            .foregroundColor(DS.textMuted)
                            .italic()
                    }
                }

                // Actions (expanded, not editing)
                if isExpanded && !isEditing {
                    HStack(spacing: 10) {
                        Button {
                            enterEditMode()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 9))
                                .foregroundColor(DS.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                                .foregroundColor(DS.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 120, maxWidth: 180, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isEditing ? DS.borderActive : (isHovered ? DS.border : DS.borderSubtle))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accentColor.opacity(isEditing ? 0.6 : (isHovered ? 0.4 : 0.2)), lineWidth: isEditing ? 1.5 : 1)
                )
        )
        .scaleEffect(isHovered && !isEditing ? 1.01 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            enterEditMode()
        }
        .onTapGesture(count: 1) {
            if !isEditing {
                onTap()
            }
        }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .offset(
            x: (annotation.customOffset?.x ?? 0) + dragOffset.width,
            y: (annotation.customOffset?.y ?? 0) + dragOffset.height
        )
        .zIndex(isDragging || annotation.hasCustomPosition ? 1 : 0)
        .highPriorityGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    let newOffset = CGPoint(
                        x: (annotation.customOffset?.x ?? 0) + value.translation.width,
                        y: (annotation.customOffset?.y ?? 0) + value.translation.height
                    )
                    dragOffset = .zero
                    onPositionChange(newOffset)
                }
        )
        .animation(isDragging ? nil : ProMotionSprings.snappy, value: dragOffset)
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if !isFocused && isEditing {
                commitEdit()
            }
        }
        .onKeyPress(.escape) {
            if isEditing {
                cancelEdit()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Edit Actions

    private func enterEditMode() {
        editContent = annotation.content
        withAnimation(ProMotionSprings.snappy) {
            isEditing = true
        }
        // Delay focus to next run loop so TextEditor is mounted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTextFieldFocused = true
        }
    }

    private func commitEdit() {
        let newContent = editContent
        withAnimation(ProMotionSprings.snappy) {
            isEditing = false
        }
        if newContent != annotation.content {
            onEdit(newContent)
        }
    }

    private func cancelEdit() {
        withAnimation(ProMotionSprings.snappy) {
            isEditing = false
        }
        editContent = annotation.content
    }
}

// MARK: - Preview

#if DEBUG
struct TranscriptSpineView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.bg
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
                onAnnotationEdit: { annotation, newContent in print("Edit: \(annotation.content) -> \(newContent)") },
                onAnnotationDelete: { annotation in print("Delete: \(annotation.content)") },
                onAnnotationPositionChange: { annotation, offset in print("Move: \(annotation.content) to \(offset)") },
                onCreateHighlightAnnotation: { sectionID, type, text, range in print("Highlight: \(type.label) on '\(text)' in section \(sectionID)") }
            )
            .frame(width: 700, height: 600)
        }
    }
}
#endif
