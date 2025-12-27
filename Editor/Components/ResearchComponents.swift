// CosmoOS/Editor/Components/ResearchComponents.swift
// Premium Research Design System
// Mirrors the polish of ConnectionComponents for research entities

import SwiftUI
import WebKit
import AppKit

// MARK: - Research Design System
struct ResearchDesign {
    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 24
    static let heroAspectRatio: CGFloat = 16.0 / 9.0
    static let heroMaxHeight: CGFloat = 560  // Increased to fit video controls at max content width
    static let maxContentWidth: CGFloat = 1000
    static let horizontalPadding: CGFloat = 40
    static let sectionSpacing: CGFloat = 24
    
    // Source-specific accent colors
    static func accentColor(for sourceType: ResearchRichContent.SourceType) -> Color {
        switch sourceType {
        case .youtube, .youtubeShort: return CosmoColors.softRed
        case .twitter, .xPost: return CosmoColors.skyBlue
        case .threads: return Color(hex: "#000000")
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel: return Color(hex: "#DD2A7B")
        case .tiktok: return Color(hex: "#000000")
        case .loom: return Color(hex: "#625DF5")  // Loom purple
        case .rawNote: return CosmoColors.lavender
        case .pdf: return CosmoColors.coral
        case .podcast: return CosmoColors.coral
        case .article, .book: return CosmoColors.skyBlue
        case .website, .other: return CosmoColors.emerald
        case .unknown: return CosmoMentionColors.research
        }
    }

    static func icon(for sourceType: ResearchRichContent.SourceType) -> String {
        switch sourceType {
        case .youtube, .youtubeShort: return "play.rectangle.fill"
        case .twitter, .xPost: return "bubble.left.fill"
        case .threads: return "at"
        case .instagram, .instagramReel, .instagramPost, .instagramCarousel: return "camera.fill"
        case .tiktok: return "video.fill"
        case .loom: return "video.bubble.fill"
        case .rawNote: return "note.text"
        case .pdf: return "doc.fill"
        case .podcast: return "headphones"
        case .article: return "doc.text"
        case .book: return "book.fill"
        case .website, .other: return "globe"
        case .unknown: return "magnifyingglass"
        }
    }

    static func label(for sourceType: ResearchRichContent.SourceType) -> String {
        switch sourceType {
        case .youtube: return "YouTube"
        case .youtubeShort: return "YouTube Short"
        case .twitter: return "Twitter"
        case .xPost: return "X Post"
        case .threads: return "Threads"
        case .instagram: return "Instagram"
        case .instagramReel: return "Instagram Reel"
        case .instagramPost: return "Instagram Post"
        case .instagramCarousel: return "Instagram Carousel"
        case .tiktok: return "TikTok"
        case .loom: return "Loom"
        case .rawNote: return "Note"
        case .pdf: return "PDF"
        case .podcast: return "Podcast"
        case .article: return "Article"
        case .book: return "Book"
        case .website: return "Website"
        case .other: return "Other"
        case .unknown: return "Research"
        }
    }
}

// MARK: - Research Hero Section
/// Large 16:9 video embed or website preview - the visual anchor
struct ResearchHeroSection: View {
    let sourceType: ResearchRichContent.SourceType
    let thumbnailUrl: String?
    let videoId: String?
    let loomId: String?
    let screenshotImage: NSImage?
    let twitterEmbedHtml: String?

    @State private var isHovered = false
    @State private var showEmbeddedPlayer = false
    @State private var isAppeared = false
    
    private var accentColor: Color {
        ResearchDesign.accentColor(for: sourceType)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Background placeholder - uses .fit to maintain exact 16:9 without overflow
                Color.black
                    .frame(maxWidth: .infinity)
                    .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)

                // Content based on source type
                switch sourceType {
                case .youtube, .youtubeShort:
                    youtubeHero
                case .loom:
                    loomHero
                case .twitter, .xPost:
                    twitterHero
                case .website:
                    websiteHero
                case .pdf:
                    pdfHero
                case .threads, .instagram, .instagramReel, .instagramPost, .instagramCarousel, .tiktok, .rawNote, .podcast, .article, .book, .other, .unknown:
                    genericHero
                }
            }
            // For YouTube and Loom, allow full 16:9 ratio; for others, use maxHeight constraint
            .frame(maxWidth: .infinity)
            .frame(maxHeight: (sourceType == .youtube || sourceType == .loom) ? nil : ResearchDesign.heroMaxHeight)
            .clipShape(RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius)
                    .stroke(accentColor.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
            )
            .shadow(
                color: accentColor.opacity(isHovered ? 0.15 : 0.08),
                radius: isHovered ? 20 : 12,
                y: isHovered ? 8 : 4
            )
            .scaleEffect(isHovered ? 1.005 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
            .onHover { isHovered = $0 }
            .opacity(isAppeared ? 1 : 0)
            .offset(y: isAppeared ? 0 : 20)
            .animation(FocusModeAnimations.backgroundEntry, value: isAppeared)
            .onAppear { isAppeared = true }
        }
    }
    
    // MARK: - YouTube Hero
    @ViewBuilder
    private var youtubeHero: some View {
        if showEmbeddedPlayer, let videoId = videoId {
            // Use .fit to ensure the full video is visible without cropping
            // This maintains 16:9 aspect ratio and shows all controls
            YouTubeEmbedView(videoId: videoId)
                .frame(maxWidth: .infinity)
                .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)
        } else if let thumbnailUrl = thumbnailUrl, let url = URL(string: thumbnailUrl) {
            ZStack {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.8)
                    @unknown default:
                        placeholderView
                    }
                }
                .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)

                // Play button overlay
                playButtonOverlay
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showEmbeddedPlayer = true
                }
            }
        } else {
            placeholderView
        }
    }
    
    private var playButtonOverlay: some View {
        ZStack {
            // Gradient overlay for contrast
            LinearGradient(
                colors: [.black.opacity(0.3), .clear, .black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Play button
            Circle()
                .fill(.white.opacity(0.95))
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(CosmoColors.softRed)
                        .offset(x: 3)
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)
            
            // YouTube badge
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 12))
                        Text("YouTube")
                            .font(CosmoTypography.labelSmall)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                    
                    Spacer()
                }
                .padding(16)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Loom Hero
    @ViewBuilder
    private var loomHero: some View {
        if showEmbeddedPlayer, let loomId = loomId {
            LoomEmbedView(videoId: loomId)
                .frame(maxWidth: .infinity)
                .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)
        } else if let thumbnailUrl = thumbnailUrl, let url = URL(string: thumbnailUrl) {
            ZStack {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        loomPlaceholderView
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.8)
                    @unknown default:
                        loomPlaceholderView
                    }
                }
                .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)

                // Play button overlay for Loom
                loomPlayButtonOverlay
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showEmbeddedPlayer = true
                }
            }
        } else if let loomId = loomId {
            // Fallback: show embed directly if no thumbnail
            LoomEmbedView(videoId: loomId)
                .frame(maxWidth: .infinity)
                .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)
        } else {
            loomPlaceholderView
        }
    }

    private var loomPlayButtonOverlay: some View {
        ZStack {
            // Gradient overlay for contrast
            LinearGradient(
                colors: [.black.opacity(0.3), .clear, .black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Play button
            Circle()
                .fill(.white.opacity(0.95))
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: "#625DF5"))
                        .offset(x: 3)
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)

            // Loom badge
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "video.bubble.fill")
                            .font(.system(size: 12))
                        Text("Loom")
                            .font(CosmoTypography.labelSmall)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "#625DF5").opacity(0.8), in: Capsule())

                    Spacer()
                }
                .padding(16)

                Spacer()
            }
        }
    }

    private var loomPlaceholderView: some View {
        RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "#625DF5").opacity(0.15),
                        Color(hex: "#625DF5").opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "video.bubble.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color(hex: "#625DF5"))
                    Text("Loom Recording")
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textSecondary)
                }
            )
    }

    // MARK: - Twitter Hero
    @ViewBuilder
    private var twitterHero: some View {
        if let html = twitterEmbedHtml, !html.isEmpty {
            TwitterEmbedView(html: html)
                .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)
        } else {
            placeholderView
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 40))
                            .foregroundColor(CosmoColors.skyBlue)
                        Text("Twitter Post")
                            .font(CosmoTypography.body)
                            .foregroundColor(CosmoColors.textSecondary)
                    }
                )
        }
    }
    
    // MARK: - Website Hero
    @ViewBuilder
    private var websiteHero: some View {
        if let image = screenshotImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)
        } else if let thumbnailUrl = thumbnailUrl, let url = URL(string: thumbnailUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholderView
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.system(size: 40))
                                    .foregroundColor(CosmoColors.emerald)
                                Text("Website")
                                    .font(CosmoTypography.body)
                                    .foregroundColor(CosmoColors.textSecondary)
                            }
                        )
                @unknown default:
                    placeholderView
                }
            }
            .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)
        } else {
            placeholderView
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 40))
                            .foregroundColor(CosmoColors.emerald)
                        Text("Website")
                            .font(CosmoTypography.body)
                            .foregroundColor(CosmoColors.textSecondary)
                    }
                )
        }
    }
    
    // MARK: - PDF Hero
    private var pdfHero: some View {
        placeholderView
            .overlay(
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white)
                            .frame(width: 80, height: 100)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        
                        VStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 32))
                                .foregroundColor(CosmoColors.coral)
                            
                            Text("PDF")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(CosmoColors.coral)
                        }
                    }
                    
                    Text("PDF Document")
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textSecondary)
                }
            )
    }
    
    // MARK: - Generic Hero
    private var genericHero: some View {
        placeholderView
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(CosmoMentionColors.research)
                    Text("Research")
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textSecondary)
                }
            )
    }
    
    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        CosmoColors.mistGrey.opacity(0.5),
                        CosmoColors.glassGrey.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(ResearchDesign.heroAspectRatio, contentMode: .fit)
    }
}

// MARK: - YouTube Embed View
struct YouTubeEmbedView: NSViewRepresentable {
    let videoId: String
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Use HTML wrapper with YouTube IFrame Player API for proper embedding
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { 
                    width: 100%; 
                    height: 100%; 
                    background: #000;
                    overflow: hidden;
                }
                .video-container {
                    position: relative;
                    width: 100%;
                    height: 100%;
                }
                iframe {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    border: none;
                }
            </style>
        </head>
        <body>
            <div class="video-container">
                <iframe 
                    src="https://www.youtube-nocookie.com/embed/\(videoId)?autoplay=0&rel=0&modestbranding=1&playsinline=1&enablejsapi=1&origin=https://cosmoos.local"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                    allowfullscreen>
                </iframe>
            </div>
        </body>
        </html>
        """
        nsView.loadHTMLString(html, baseURL: URL(string: "https://cosmoos.local"))
    }
}

// MARK: - Twitter Embed View
struct TwitterEmbedView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Loom Embed View
struct LoomEmbedView: NSViewRepresentable {
    let videoId: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Use HTML wrapper with Loom embed for proper embedding
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    width: 100%;
                    height: 100%;
                    background: #000;
                    overflow: hidden;
                }
                .video-container {
                    position: relative;
                    width: 100%;
                    height: 100%;
                }
                iframe {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    border: none;
                }
            </style>
        </head>
        <body>
            <div class="video-container">
                <iframe
                    src="https://www.loom.com/embed/\(videoId)?hide_owner=true&hide_share=true&hide_title=true&hideEmbedTopBar=true"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen"
                    allowfullscreen>
                </iframe>
            </div>
        </body>
        </html>
        """
        nsView.loadHTMLString(html, baseURL: URL(string: "https://www.loom.com"))
    }
}

// MARK: - Smart Transcript View
/// Dual-mode transcript display with timestamped and AI-formatted views
struct SmartTranscriptView: View {
    let segments: [TranscriptSegment]
    let sections: [TranscriptSectionData]?
    let formattedTranscript: String?
    let accentColor: Color
    
    @State private var viewMode: TranscriptViewMode = .timestamped
    @State private var searchQuery = ""
    @State private var expandedSections: Set<String> = []
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var isAppeared = false
    
    enum TranscriptViewMode: String, CaseIterable {
        case timestamped = "Timestamped"
        case formatted = "Formatted"
    }
    
    private var filteredSegments: [TranscriptSegment] {
        guard !searchQuery.isEmpty else { return segments }
        return segments.filter { $0.text.localizedCaseInsensitiveContains(searchQuery) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with toggle
            header
            
            // Search bar
            if isExpanded {
                searchBar
            }
            
            // Content
            contentView
            
            // Footer
            if !isExpanded && segments.count > 5 {
                footerExpand
            }
        }
        .padding(ResearchDesign.cardPadding)
        .background(
            ZStack {
                CosmoColors.cardBackground
                accentColor.opacity(0.02)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius)
                .stroke(isHovered ? accentColor.opacity(0.3) : CosmoColors.glassGrey.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.04), radius: 12, x: 0, y: 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 20)
        .animation(FocusModeAnimations.editorEntry.delay(0.2), value: isAppeared)
        .onAppear { isAppeared = true }
    }
    
    private var header: some View {
        HStack {
            // Title with icon
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
                
                Text("Transcript")
                    .font(CosmoTypography.titleSmall)
                    .foregroundColor(CosmoColors.textPrimary)
                
                Text("\(segments.count) segments")
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
            }
            
            Spacer()
            
            // View mode toggle
            if formattedTranscript != nil {
                HStack(spacing: 0) {
                    ForEach(TranscriptViewMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                viewMode = mode
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(CosmoTypography.labelSmall)
                                .foregroundColor(viewMode == mode ? .white : CosmoColors.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    viewMode == mode ? accentColor : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(CosmoColors.glassGrey.opacity(0.3), in: Capsule())
            }
            
            // Expand/collapse button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                    Text(isExpanded ? "Collapse" : "Expand")
                        .font(CosmoTypography.labelSmall)
                }
                .foregroundColor(CosmoColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(CosmoColors.glassGrey.opacity(0.3), in: Capsule())
            }
            .buttonStyle(.plain)
            
            // Copy button
            Button {
                let fullText = segments.map { $0.text }.joined(separator: " ")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullText, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(CosmoColors.textSecondary)
                    .padding(8)
                    .background(CosmoColors.glassGrey.opacity(0.3), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Copy transcript")
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(CosmoColors.textTertiary)
            
            TextField("Search transcript...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(CosmoTypography.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CosmoColors.mistGrey.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .timestamped:
            timestampedView
        case .formatted:
            formattedView
        }
    }
    
    private var timestampedView: some View {
        VStack(spacing: 0) {
            let displaySegments = isExpanded ? filteredSegments : Array(filteredSegments.prefix(5))
            
            ForEach(Array(displaySegments.enumerated()), id: \.element.id) { index, segment in
                TranscriptSegmentRow(
                    segment: segment,
                    accentColor: accentColor,
                    isHighlighted: !searchQuery.isEmpty && segment.text.localizedCaseInsensitiveContains(searchQuery)
                )
                
                if index < displaySegments.count - 1 {
                    Divider()
                        .opacity(0.4)
                }
            }
        }
        .background(CosmoColors.mistGrey.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    @ViewBuilder
    private var formattedView: some View {
        if let formatted = formattedTranscript {
            ScrollView {
                Text(formatted)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxHeight: isExpanded ? 500 : 200)
            .background(CosmoColors.mistGrey.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        } else {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundColor(CosmoColors.lavender)
                    Text("AI formatting not available")
                        .font(CosmoTypography.bodySmall)
                        .foregroundColor(CosmoColors.textTertiary)
                }
                .padding(24)
                Spacer()
            }
            .background(CosmoColors.mistGrey.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private var footerExpand: some View {
        HStack {
            Spacer()
            Text("Showing 5 of \(segments.count) segments")
                .font(CosmoTypography.caption)
                .foregroundColor(CosmoColors.textTertiary)
            Spacer()
        }
    }
}

// Note: TranscriptSectionData is defined in Data/Models/Research.swift

// MARK: - Transcript Segment Row
struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let accentColor: Color
    let isHighlighted: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(segment.formattedTime)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(isHovered ? accentColor : CosmoColors.textTertiary)
                .frame(width: 50, alignment: .leading)
            
            // Text content
            Text(segment.text)
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isHighlighted ? accentColor.opacity(0.1) : 
            (isHovered ? CosmoColors.mistGrey.opacity(0.4) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Research Section Card (Editable)
/// Premium card for editable content sections (Summary, Findings, Notes)
struct ResearchSectionCard: View {
    let title: String
    let subtitle: String?
    let placeholder: String
    @Binding var content: String
    let accentColor: Color
    let icon: String?
    let isPrivate: Bool
    
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var isAppeared = false
    
    init(
        title: String,
        subtitle: String? = nil,
        placeholder: String,
        content: Binding<String>,
        accentColor: Color,
        icon: String? = nil,
        isPrivate: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.placeholder = placeholder
        self._content = content
        self.accentColor = accentColor
        self.icon = icon
        self.isPrivate = isPrivate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(accentColor)
                    }
                    
                    Text(title)
                        .font(CosmoTypography.titleSmall)
                        .foregroundColor(CosmoColors.textPrimary)
                    
                    if isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(CosmoColors.textTertiary)
                    }
                }
                
                Spacer()
                
                // Status indicator
                Circle()
                    .fill(content.isEmpty ? Color.clear : accentColor)
                    .frame(width: 6, height: 6)
                    .background(
                        Circle()
                            .stroke(content.isEmpty ? CosmoColors.glassGrey : accentColor.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Subtitle
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
                    .lineLimit(2)
            }
            
            // Editor
            ZStack(alignment: .topLeading) {
                if content.isEmpty && !isFocused {
                    Text(placeholder)
                        .font(CosmoTypography.body)
                        .foregroundColor(CosmoColors.textTertiary.opacity(0.5))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $content)
                    .font(CosmoTypography.body)
                    .foregroundColor(CosmoColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 100)
            }
        }
        .padding(ResearchDesign.cardPadding)
        .background(
            ZStack {
                CosmoColors.cardBackground
                accentColor.opacity(isPrivate ? 0.05 : 0.03)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ResearchDesign.cornerRadius)
                .stroke(
                    isFocused ? accentColor.opacity(0.5) :
                    (isHovered ? CosmoColors.glassGrey : Color.clear),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(isFocused ? 0.08 : 0.04), radius: 12, x: 0, y: 6)
        .scaleEffect(isHovered && !isFocused ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        .onHover { isHovered = $0 }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 20)
        .onAppear {
            withAnimation(FocusModeAnimations.editorEntry.delay(0.1)) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Research Metadata Bar
/// Compact bar showing author, date, source type, duration
struct ResearchMetadataBar: View {
    let sourceType: ResearchRichContent.SourceType
    let author: String?
    let publishedAt: String?
    let duration: Int?
    let domain: String?
    
    private var accentColor: Color {
        ResearchDesign.accentColor(for: sourceType)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Source badge
            HStack(spacing: 6) {
                Image(systemName: ResearchDesign.icon(for: sourceType))
                    .font(.system(size: 11))
                Text(ResearchDesign.label(for: sourceType))
                    .font(CosmoTypography.labelSmall)
            }
            .foregroundColor(accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accentColor.opacity(0.1), in: Capsule())
            
            // Author
            if let author = author {
                HStack(spacing: 4) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 11))
                    Text(author)
                        .font(CosmoTypography.caption)
                }
                .foregroundColor(CosmoColors.textSecondary)
            }
            
            // Published date
            if let published = publishedAt {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text(formatDate(published))
                        .font(CosmoTypography.caption)
                }
                .foregroundColor(CosmoColors.textTertiary)
            }
            
            // Duration (for videos)
            if let duration = duration {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(formatDuration(duration))
                        .font(CosmoTypography.caption)
                }
                .foregroundColor(CosmoColors.textTertiary)
            }
            
            // Domain
            if let domain = domain {
                Text(domain)
                    .font(CosmoTypography.caption)
                    .foregroundColor(CosmoColors.textTertiary)
            }
            
            Spacer()
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins >= 60 {
            let hours = mins / 60
            let remainingMins = mins % 60
            return "\(hours)h \(remainingMins)m"
        }
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

// MARK: - URL Bar
/// Minimalist URL display with copy/open actions
struct ResearchURLBar: View {
    let url: String
    let sourceType: ResearchRichContent.SourceType
    
    @State private var showCopied = false
    @State private var isHovered = false
    
    private var accentColor: Color {
        ResearchDesign.accentColor(for: sourceType)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ResearchDesign.icon(for: sourceType))
                .font(.system(size: 14))
                .foregroundColor(accentColor)
            
            Text(url)
                .font(CosmoTypography.bodySmall)
                .foregroundColor(CosmoColors.skyBlue)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Copy button
            Button {
                copyURL()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                    Text(showCopied ? "Copied" : "Copy")
                        .font(CosmoTypography.labelSmall)
                }
                .foregroundColor(showCopied ? CosmoColors.emerald : CosmoColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(CosmoColors.glassGrey.opacity(0.3), in: Capsule())
            }
            .buttonStyle(.plain)
            
            // Open button
            if let openURL = URL(string: url) {
                Link(destination: openURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                        Text("Open")
                            .font(CosmoTypography.labelSmall)
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.1), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(CosmoColors.mistGrey.opacity(isHovered ? 0.5 : 0.3), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CosmoColors.glassGrey.opacity(0.3), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
    
    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        
        withAnimation {
            showCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

// MARK: - Research Editor Header
/// Minimal header with close, source badge, and save status
struct ResearchEditorHeaderV2: View {
    let sourceType: ResearchRichContent.SourceType
    let onClose: () -> Void
    
    private var accentColor: Color {
        ResearchDesign.accentColor(for: sourceType)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CosmoColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
            
            Spacer()
            
            // Source badge (centered)
            HStack(spacing: 6) {
                Image(systemName: ResearchDesign.icon(for: sourceType))
                    .font(.system(size: 11))
                Text(ResearchDesign.label(for: sourceType))
                    .font(CosmoTypography.labelSmall)
            }
            .foregroundColor(accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(accentColor.opacity(0.1), in: Capsule())
            
            Spacer()
            
            // Spacer to balance the close button
            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

