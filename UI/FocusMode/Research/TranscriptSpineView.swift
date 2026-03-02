// CosmoOS/UI/FocusMode/Research/TranscriptSpineView.swift
// Vertical transcript backbone with inline annotation indicators
// Notion-style comments: highlights + popover detail, no floating cards
// March 2026 — Redesigned for performance and usability

import SwiftUI

// MARK: - Transcript Spine View

/// The vertical transcript backbone for Research Focus Mode.
/// Annotations appear inline as indicator badges below highlighted text.
/// Clicking a badge or highlighted text opens a detail popover.
struct TranscriptSpineView: View {
    // MARK: - Properties

    let sections: [TranscriptSection]
    let currentTimestamp: TimeInterval

    let onSectionTap: (TranscriptSection) -> Void
    let onAddAnnotation: (TranscriptSection, AnnotationType) -> Void
    let onAnnotationEdit: (ResearchAnnotation, String) -> Void
    let onAnnotationDelete: (ResearchAnnotation) -> Void
    let onCreateHighlightAnnotation: (UUID, AnnotationType, String, NSRange) -> Void
    let onPromoteToBlock: (ResearchAnnotation) -> Void

    // MARK: - State

    @State private var hoveredSectionID: UUID?
    @State private var lastScrolledSectionID: UUID?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            transcriptHeader

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(sections) { section in
                            TranscriptSectionRow(
                                section: section,
                                isPlaying: isPlaying(section),
                                isHovered: hoveredSectionID == section.id,
                                onTap: { onSectionTap(section) },
                                onAddAnnotation: { type in onAddAnnotation(section, type) },
                                onAnnotationEdit: { annotation, newContent in
                                    onAnnotationEdit(annotation, newContent)
                                },
                                onAnnotationDelete: { annotation in
                                    onAnnotationDelete(annotation)
                                },
                                onCreateHighlightAnnotation: onCreateHighlightAnnotation,
                                onPromoteToBlock: onPromoteToBlock
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
                    // Only auto-scroll when the active section actually changes
                    if let currentSection = sections.first(where: {
                        newTime >= $0.startTime && newTime < $0.endTime
                    }), currentSection.id != lastScrolledSectionID {
                        lastScrolledSectionID = currentSection.id
                        withAnimation(ProMotionSprings.gentle) {
                            proxy.scrollTo(currentSection.id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(DS.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.borderActive.opacity(0.8), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(0.06),
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
}

// MARK: - Transcript Section Row

/// A single section in the transcript spine with inline annotation indicators
struct TranscriptSectionRow: View {
    let section: TranscriptSection
    let isPlaying: Bool
    let isHovered: Bool

    let onTap: () -> Void
    let onAddAnnotation: (AnnotationType) -> Void
    let onAnnotationEdit: (ResearchAnnotation, String) -> Void
    let onAnnotationDelete: (ResearchAnnotation) -> Void
    let onCreateHighlightAnnotation: (UUID, AnnotationType, String, NSRange) -> Void
    let onPromoteToBlock: (ResearchAnnotation) -> Void

    @State private var selectedTextInfo: (String, NSRange)? = nil
    @State private var showTypePickerPopover = false
    @State private var showAnnotationDetail = false
    @State private var showHighlightPopover = false
    @State private var activeAnnotationType: AnnotationType? = nil
    @State private var activeAnnotationID: UUID? = nil

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
                    showTypePickerPopover = true
                },
                onHighlightClicked: { annotationID in
                    activeAnnotationID = annotationID
                    activeAnnotationType = nil
                    showHighlightPopover = true
                }
            )
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .popover(isPresented: $showHighlightPopover) {
                AnnotationDetailPopover(
                    annotations: filteredAnnotationsForPopover,
                    sectionText: section.text,
                    onEdit: { annotation, newContent in
                        onAnnotationEdit(annotation, newContent)
                    },
                    onDelete: { annotation in
                        onAnnotationDelete(annotation)
                        if section.annotations.count <= 1 {
                            showHighlightPopover = false
                        }
                    },
                    onPromoteToBlock: { annotation in
                        onPromoteToBlock(annotation)
                    }
                )
            }

            // Inline annotation indicators
            if !section.annotations.isEmpty {
                annotationIndicators
            }

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
        // Type picker popover (for creating new annotations from text selection)
        .popover(isPresented: $showTypePickerPopover) {
            AnnotationTypePickerPopover(
                selectedText: selectedTextInfo?.0 ?? "",
                onSelect: { type in
                    if let info = selectedTextInfo {
                        onCreateHighlightAnnotation(section.id, type, info.0, info.1)
                    }
                    showTypePickerPopover = false
                    selectedTextInfo = nil
                },
                onCancel: {
                    showTypePickerPopover = false
                    selectedTextInfo = nil
                }
            )
        }
    }

    // MARK: - Annotation Indicators

    private var annotationIndicators: some View {
        HStack(spacing: 6) {
            ForEach(groupedAnnotationCounts, id: \.type) { group in
                Button {
                    activeAnnotationType = group.type
                    activeAnnotationID = nil
                    showAnnotationDetail = true
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(group.type.color)
                            .frame(width: 6, height: 6)
                        Image(systemName: group.type.icon)
                            .font(.system(size: 9))
                        if group.count > 1 {
                            Text("\(group.count)")
                                .font(.system(size: 9, weight: .medium))
                        }
                    }
                    .foregroundColor(group.type.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(group.type.color.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
        .popover(isPresented: $showAnnotationDetail) {
            AnnotationDetailPopover(
                annotations: filteredAnnotationsForPopover,
                sectionText: section.text,
                onEdit: { annotation, newContent in
                    onAnnotationEdit(annotation, newContent)
                },
                onDelete: { annotation in
                    onAnnotationDelete(annotation)
                    // Close popover if no annotations left
                    if section.annotations.count <= 1 {
                        showAnnotationDetail = false
                    }
                },
                onPromoteToBlock: { annotation in
                    onPromoteToBlock(annotation)
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

    private struct AnnotationGroup: Hashable {
        let type: AnnotationType
        let count: Int
    }

    private var groupedAnnotationCounts: [AnnotationGroup] {
        var counts: [AnnotationType: Int] = [:]
        for annotation in section.annotations {
            counts[annotation.type, default: 0] += 1
        }
        return counts.map { AnnotationGroup(type: $0.key, count: $0.value) }
            .sorted { $0.type.rawValue < $1.type.rawValue }
    }

    private var filteredAnnotationsForPopover: [ResearchAnnotation] {
        if let id = activeAnnotationID {
            // Clicked a specific highlight — show that annotation
            return section.annotations.filter { $0.id == id }
        }
        if let type = activeAnnotationType {
            // Clicked a type badge — show all annotations of that type
            return section.annotations.filter { $0.type == type }
        }
        return section.annotations
    }

    private var spineColor: Color {
        isPlaying ? CosmoColors.blockResearch : DS.borderActive
    }
}

// MARK: - Annotation Detail Popover

/// Notion-style annotation detail popover. Shows annotation content,
/// highlighted text excerpt, and actions (edit, delete, add to canvas).
struct AnnotationDetailPopover: View {
    let annotations: [ResearchAnnotation]
    let sectionText: String
    let onEdit: (ResearchAnnotation, String) -> Void
    let onDelete: (ResearchAnnotation) -> Void
    let onPromoteToBlock: (ResearchAnnotation) -> Void

    @State private var editingID: UUID? = nil
    @State private var editContent: String = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group annotations by type
            ForEach(AnnotationType.allCases, id: \.rawValue) { type in
                let ofType = annotations.filter { $0.type == type }
                if !ofType.isEmpty {
                    typeSection(type: type, annotations: ofType)
                }
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.borderActive, lineWidth: 1)
                )
        )
    }

    // MARK: - Type Section

    @ViewBuilder
    private func typeSection(type: AnnotationType, annotations: [ResearchAnnotation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type header
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(type.color)
                    .frame(width: 3, height: 14)
                Image(systemName: type.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text("\(type.label.uppercased()) (\(annotations.count))")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundColor(type.color)

            ForEach(annotations) { annotation in
                annotationRow(annotation)

                if annotation.id != annotations.last?.id {
                    Divider().opacity(0.3)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Annotation Row

    @ViewBuilder
    private func annotationRow(_ annotation: ResearchAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Highlighted text excerpt
            if let highlighted = annotation.highlightedText, !highlighted.isEmpty {
                Text("\"\(highlighted.prefix(80))\(highlighted.count > 80 ? "..." : "")\"")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .italic()
                    .lineLimit(2)
            }

            // Content (editable)
            if editingID == annotation.id {
                editableContent(annotation)
            } else {
                staticContent(annotation)
            }

            // Action buttons
            actionButtons(annotation)
        }
    }

    @ViewBuilder
    private func staticContent(_ annotation: ResearchAnnotation) -> some View {
        if !annotation.content.isEmpty {
            Text(annotation.content)
                .font(.system(size: 12))
                .foregroundColor(DS.text)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture {
                    enterEditMode(annotation)
                }
        } else {
            Text("Click to add a note...")
                .font(.system(size: 12))
                .foregroundColor(DS.textMuted)
                .italic()
                .onTapGesture {
                    enterEditMode(annotation)
                }
        }
    }

    @ViewBuilder
    private func editableContent(_ annotation: ResearchAnnotation) -> some View {
        ZStack(alignment: .topLeading) {
            if editContent.isEmpty {
                Text("Add a note...")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)
                    .padding(.top, 4)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $editContent)
                .font(.system(size: 12))
                .foregroundColor(DS.text)
                .scrollContentBackground(.hidden)
                .focused($isEditing)
                .frame(minHeight: 36, maxHeight: 100)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DS.border)
        )
        .onChange(of: isEditing) { _, focused in
            if !focused && editingID == annotation.id {
                commitEdit(annotation)
            }
        }
        .onKeyPress(.escape) {
            cancelEdit()
            return .handled
        }
    }

    @ViewBuilder
    private func actionButtons(_ annotation: ResearchAnnotation) -> some View {
        HStack(spacing: 12) {
            Button {
                if editingID == annotation.id {
                    commitEdit(annotation)
                } else {
                    enterEditMode(annotation)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: editingID == annotation.id ? "checkmark" : "pencil")
                        .font(.system(size: 9))
                    Text(editingID == annotation.id ? "Save" : "Edit")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(DS.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                onPromoteToBlock(annotation)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 9))
                    Text("Add to Canvas")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(DS.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onDelete(annotation)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
                    .foregroundColor(DS.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Edit Actions

    private func enterEditMode(_ annotation: ResearchAnnotation) {
        editContent = annotation.content
        editingID = annotation.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isEditing = true
        }
    }

    private func commitEdit(_ annotation: ResearchAnnotation) {
        let newContent = editContent
        editingID = nil
        if newContent != annotation.content {
            onEdit(annotation, newContent)
        }
    }

    private func cancelEdit() {
        editingID = nil
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
                onAnnotationEdit: { annotation, newContent in print("Edit: \(annotation.content) -> \(newContent)") },
                onAnnotationDelete: { annotation in print("Delete: \(annotation.content)") },
                onCreateHighlightAnnotation: { sectionID, type, text, range in print("Highlight: \(type.label) on '\(text)' in section \(sectionID)") },
                onPromoteToBlock: { annotation in print("Promote: \(annotation.content)") }
            )
            .frame(width: 700, height: 600)
        }
    }
}
#endif
