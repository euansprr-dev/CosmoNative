// CosmoOS/UI/FocusMode/Research/InstagramCarouselLayout.swift
// Carousel layout for Instagram posts with multiple images/videos
// Per Instagram Research PRD Addendum

import SwiftUI
import AVKit

// MARK: - Instagram Carousel Layout

/// Standard top-down layout for Instagram carousels with per-slide notes
struct InstagramCarouselLayout: View {
    let atom: Atom
    let instagramData: InstagramData
    let onAnnotationAdd: (Int, InstagramAnnotation.AnnotationType) -> Void
    let onAnnotationEdit: (InstagramAnnotation) -> Void
    let onAnnotationDelete: (UUID) -> Void

    @State private var currentSlideIndex: Int = 0
    @State private var slideAnnotations: [Int: [InstagramAnnotation]] = [:]

    var body: some View {
        VStack(spacing: 24) {
            // Carousel viewer
            carouselViewer

            // Notes for current slide
            currentSlideNotes
        }
    }

    // MARK: - Carousel Viewer

    private var carouselViewer: some View {
        VStack(spacing: 12) {
            // Main slide display
            ZStack {
                if let items = instagramData.carouselItems, !items.isEmpty {
                    // Current slide
                    CarouselSlideView(item: items[currentSlideIndex])
                        .id(currentSlideIndex)
                        .transition(.opacity)

                    // Navigation arrows
                    HStack {
                        // Previous
                        if currentSlideIndex > 0 {
                            Button {
                                withAnimation {
                                    currentSlideIndex -= 1
                                }
                            } label: {
                                navigationArrow(direction: .left)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        // Next
                        if currentSlideIndex < items.count - 1 {
                            Button {
                                withAnimation {
                                    currentSlideIndex += 1
                                }
                            } label: {
                                navigationArrow(direction: .right)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    // Fallback for no carousel items
                    emptyCarouselState
                }
            }
            .frame(width: 480, height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
            )

            // Dot indicators
            if let items = instagramData.carouselItems, items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<items.count, id: \.self) { index in
                        Circle()
                            .fill(dotColor(for: index))
                            .frame(width: 8, height: 8)
                            .onTapGesture {
                                withAnimation {
                                    currentSlideIndex = index
                                }
                            }
                    }
                }
            }

            // Slide counter and metadata
            HStack(spacing: 12) {
                // Counter
                if let items = instagramData.carouselItems {
                    Text("\(currentSlideIndex + 1) / \(items.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }

                Text("·")
                    .foregroundColor(.white.opacity(0.3))

                // Username
                if let username = instagramData.authorUsername {
                    Text("@\(username)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Text("·")
                    .foregroundColor(.white.opacity(0.3))

                // Type badge
                Text("Carousel")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#E4405F"))

                if let items = instagramData.carouselItems {
                    Text("· \(items.count) items")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        if index == currentSlideIndex {
            return .white
        }
        // Filled if has annotation
        let hasAnnotation = getAnnotationsForSlide(index).count > 0
        return hasAnnotation ? Color(hex: "#E4405F") : Color.white.opacity(0.3)
    }

    private func navigationArrow(direction: NavigationDirection) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    private var emptyCarouselState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))

            Text("Could not load carousel")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Notes for Current Slide

    private var currentSlideNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("NOTES FOR SLIDE \(currentSlideIndex + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                // Add annotation buttons
                HStack(spacing: 8) {
                    annotationButton(type: .note, icon: "note.text", color: CosmoColors.emerald)
                    annotationButton(type: .question, icon: "questionmark.circle", color: .orange)
                    annotationButton(type: .insight, icon: "lightbulb.fill", color: .purple)
                }
            }

            // Existing annotations for this slide
            let annotations = getAnnotationsForSlide(currentSlideIndex)
            if annotations.isEmpty {
                emptyNotesState
            } else {
                ForEach(annotations) { annotation in
                    CarouselAnnotationView(
                        annotation: annotation,
                        onEdit: { onAnnotationEdit(annotation) },
                        onDelete: { onAnnotationDelete(annotation.id) }
                    )
                }
            }
        }
        .padding()
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.2))
        )
    }

    private func annotationButton(type: InstagramAnnotation.AnnotationType, icon: String, color: Color) -> some View {
        Button {
            onAnnotationAdd(currentSlideIndex, type)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text("Add \(type.rawValue.capitalized)")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyNotesState: some View {
        HStack {
            Spacer()
            Text("No notes for this slide yet")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
        .padding(.vertical, 20)
    }

    // MARK: - Helpers

    private func getAnnotationsForSlide(_ index: Int) -> [InstagramAnnotation] {
        // Get all annotations that have slideIndex matching this slide
        guard let transcript = instagramData.manualTranscript else { return [] }

        return transcript.sections.flatMap { section in
            section.annotations.filter { $0.slideIndex == index }
        }
    }

    enum NavigationDirection {
        case left, right
    }
}

// MARK: - Carousel Slide View

struct CarouselSlideView: View {
    let item: CarouselItem

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            if item.mediaType == .video {
                // Video slide
                if let player = player {
                    VideoPlayer(player: player)
                        .disabled(true)
                } else {
                    // Loading video
                    Rectangle()
                        .fill(Color.black)
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                        .onAppear {
                            setupVideoPlayer()
                        }
                }

                // Play button overlay
                if !isPlaying {
                    Button {
                        togglePlayback()
                    } label: {
                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .offset(x: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Image slide
                AsyncImage(url: item.mediaURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .overlay(ProgressView().tint(.white))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white.opacity(0.3))
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func setupVideoPlayer() {
        player = AVPlayer(url: item.mediaURL)
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
}

// MARK: - Carousel Annotation View

struct CarouselAnnotationView: View {
    let annotation: InstagramAnnotation
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Type icon
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(annotationColor)
                .frame(width: 24, height: 24)
                .background(annotationColor.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                // Type label
                Text(annotation.type.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(annotationColor)

                // Content
                Text(annotation.content)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                }
                .foregroundColor(.white.opacity(0.4))
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(annotationColor.opacity(0.08))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var iconName: String {
        switch annotation.type {
        case .note: return "note.text"
        case .question: return "questionmark.circle"
        case .insight: return "lightbulb.fill"
        }
    }

    private var annotationColor: Color {
        switch annotation.type {
        case .note: return CosmoColors.emerald
        case .question: return .orange
        case .insight: return .purple
        }
    }
}
